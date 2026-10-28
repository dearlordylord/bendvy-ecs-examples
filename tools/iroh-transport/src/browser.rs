use crate::{ALPN, MAX_MESSAGE, invitation, parse_invitation};
use iroh::{
    Endpoint, RelayMode, RelayUrl,
    endpoint::{Connection, Incoming, presets},
};
use js_sys::{Function, Object, Reflect, Uint8Array};
use n0_future::{
    task,
    time::{Duration, Instant, sleep_until, timeout},
};
use std::{cell::RefCell, collections::BTreeMap, rc::Rc};
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::spawn_local;

const MAX_IN_FLIGHT: usize = 16;
const MAX_PENDING_BYTES: usize = 4 * MAX_MESSAGE;
const MAX_OFFERS: usize = 16;
const TIMEOUT: Duration = Duration::from_secs(20);
const RELAY_URL: &str = "https://quint-graph.fly.dev";

struct Peer {
    connection: Connection,
    operation: u32,
}

struct Offer {
    incoming: Incoming,
    expires: Instant,
}

struct Inner {
    endpoint: Endpoint,
    callback: Option<Function>,
    connection: Option<Peer>,
    generation: u64,
    pending: Option<u32>,
    last_operation: u32,
    closed: bool,
    sends: usize,
    send_bytes: usize,
    offers: BTreeMap<u32, Offer>,
    offer_timer: Option<task::AbortHandle>,
    operations: usize,
    next_offer: u32,
}

type Shared = Rc<RefCell<Inner>>;

fn failure(message: impl ToString) -> JsValue {
    js_sys::Error::new(&message.to_string()).into()
}

struct Event<'a> {
    kind: &'a str,
    peer: Option<&'a str>,
    message: Option<&'a str>,
    bytes: Option<&'a [u8]>,
    operation: Option<u32>,
    connection: Option<u32>,
    offer: Option<u32>,
}

impl<'a> Event<'a> {
    fn new(kind: &'a str) -> Self {
        Self {
            kind,
            peer: None,
            message: None,
            bytes: None,
            operation: None,
            connection: None,
            offer: None,
        }
    }
}

fn emit(shared: &Shared, event: Event<'_>) {
    // JavaScript callbacks may synchronously close or disconnect the endpoint.
    let callback = shared.borrow().callback.clone();
    if let Some(callback) = callback {
        emit_callback(&callback, event);
    }
}

fn emit_callback(callback: &Function, value: Event<'_>) {
    let event = Object::new();
    Reflect::set(&event, &"type".into(), &value.kind.into()).ok();
    Reflect::set(&event, &"path".into(), &"relay".into()).ok();
    Reflect::set(&event, &"relayUrl".into(), &RELAY_URL.into()).ok();
    if let Some(peer) = value.peer {
        Reflect::set(&event, &"peerId".into(), &peer.into()).ok();
    }
    if let Some(message) = value.message {
        Reflect::set(&event, &"message".into(), &message.into()).ok();
    }
    if let Some(bytes) = value.bytes {
        Reflect::set(&event, &"bytes".into(), &Uint8Array::from(bytes)).ok();
    }
    for (key, value) in [
        ("operationId", value.operation),
        ("connectionId", value.connection),
        ("offerId", value.offer),
    ] {
        if let Some(value) = value {
            Reflect::set(&event, &key.into(), &value.into()).ok();
        }
    }
    callback.call1(&JsValue::NULL, &event).ok();
}

fn current(shared: &Shared, generation: u64) -> bool {
    let inner = shared.borrow();
    !inner.closed && inner.generation == generation
}

fn begin(inner: &mut Inner, operation: u32) -> Result<u64, JsValue> {
    if inner.closed || inner.pending.is_some() || inner.connection.is_some() {
        return Err(failure(
            "Endpoint is closed, connecting or already connected",
        ));
    }
    if inner.operations >= MAX_IN_FLIGHT {
        return Err(failure("Too many native connection operations"));
    }
    if operation == 0 || operation <= inner.last_operation {
        return Err(failure("Transport operation must be fresh and nonzero"));
    }
    inner.generation = inner
        .generation
        .checked_add(1)
        .ok_or_else(|| failure("Transport generation exhausted"))?;
    inner.last_operation = operation;
    inner.pending = Some(operation);
    inner.operations += 1;
    Ok(inner.generation)
}

fn install(
    shared: &Shared,
    connection: Connection,
    generation: u64,
    operation: u32,
) -> Result<(), JsValue> {
    {
        let mut inner = shared.borrow_mut();
        if inner.closed
            || inner.generation != generation
            || inner.pending != Some(operation)
            || inner.connection.is_some()
        {
            connection.close(1u32.into(), b"Connection operation is no longer current");
            return Err(failure("Connection attempt was cancelled"));
        }
        inner.pending = None;
        inner.connection = Some(Peer {
            connection: connection.clone(),
            operation,
        });
    }
    let peer = connection.remote_id().to_string();
    emit(
        shared,
        Event {
            peer: Some(&peer),
            operation: Some(operation),
            connection: Some(operation),
            ..Event::new("connected")
        },
    );
    let shared = shared.clone();
    spawn_local(async move {
        let error = loop {
            let mut stream = match connection.accept_uni().await {
                Ok(stream) => stream,
                Err(error) => break error.to_string(),
            };
            let bytes = match timeout(TIMEOUT, stream.read_to_end(MAX_MESSAGE)).await {
                Ok(Ok(bytes)) => bytes,
                Ok(Err(error)) => {
                    connection.close(2u32.into(), b"Invalid or oversized transport frame");
                    break error.to_string();
                }
                Err(_) => {
                    connection.close(3u32.into(), b"Transport frame timed out");
                    break "Incoming frame timed out".into();
                }
            };
            if !current(&shared, generation) {
                return;
            }
            emit(
                &shared,
                Event {
                    peer: Some(&peer),
                    bytes: Some(&bytes),
                    connection: Some(operation),
                    ..Event::new("message")
                },
            );
        };
        if current(&shared, generation) {
            {
                let mut inner = shared.borrow_mut();
                inner.connection = None;
            }
            emit(
                &shared,
                Event {
                    peer: Some(&peer),
                    message: Some(&error),
                    connection: Some(operation),
                    ..Event::new("disconnected")
                },
            );
        }
    });
    Ok(())
}

async fn finish_connection(
    shared: &Shared,
    generation: u64,
    operation: u32,
    result: Result<Connection, JsValue>,
) -> Result<(), JsValue> {
    if !current(shared, generation) {
        if let Ok(connection) = result {
            connection.close(0u32.into(), b"Connection operation was cancelled");
        }
        return Err(failure("Connection attempt was cancelled"));
    }
    match result {
        Ok(connection) => install(shared, connection, generation, operation),
        Err(error) => {
            let mut inner = shared.borrow_mut();
            if inner.pending == Some(operation) {
                inner.pending = None;
            }
            Err(error)
        }
    }
}

struct NativeOperation(Shared);

impl Drop for NativeOperation {
    fn drop(&mut self) {
        let mut inner = self.0.borrow_mut();
        inner.operations = inner.operations.saturating_sub(1);
    }
}

struct NativeWrite {
    shared: Shared,
    bytes: usize,
}

impl Drop for NativeWrite {
    fn drop(&mut self) {
        let mut inner = self.shared.borrow_mut();
        inner.sends = inner.sends.saturating_sub(1);
        inner.send_bytes = inner.send_bytes.saturating_sub(self.bytes);
    }
}

fn expire_offers(shared: &Shared) {
    {
        let inner = shared.borrow();
        if inner.offer_timer.is_some() || inner.offers.is_empty() || inner.closed {
            return;
        }
    }
    let weak = Rc::downgrade(shared);
    let timer = task::spawn(async move {
        loop {
            let deadline = weak.upgrade().and_then(|shared| {
                let mut inner = shared.borrow_mut();
                if inner.closed || inner.offers.is_empty() {
                    inner.offer_timer = None;
                    None
                } else {
                    inner.offers.values().map(|offer| offer.expires).min()
                }
            });
            let Some(deadline) = deadline else {
                return;
            };
            sleep_until(deadline).await;
            let Some(shared) = weak.upgrade() else {
                return;
            };
            let expired = {
                let mut inner = shared.borrow_mut();
                let now = Instant::now();
                let ids: Vec<_> = inner
                    .offers
                    .iter()
                    .filter(|(_, offer)| offer.expires <= now)
                    .map(|(id, _)| *id)
                    .collect();
                ids.into_iter()
                    .filter_map(|id| inner.offers.remove(&id))
                    .collect::<Vec<_>>()
            };
            for offer in expired {
                offer.incoming.refuse();
            }
        }
    });
    shared.borrow_mut().offer_timer = Some(timer.abort_handle());
}

/// Native resource owner. Bend chooses admission, retries, deadlines and write order.
#[wasm_bindgen]
pub struct Transport {
    inner: Shared,
}

#[wasm_bindgen]
impl Transport {
    #[wasm_bindgen(js_name = create)]
    pub async fn create(callback: Function) -> Result<Transport, JsValue> {
        console_error_panic_hook::set_once();
        let relay: RelayUrl = RELAY_URL.parse().map_err(failure)?;
        let endpoint = timeout(
            TIMEOUT,
            Endpoint::builder(presets::N0)
                .relay_mode(RelayMode::Custom([relay].into_iter().collect()))
                .alpns(vec![ALPN.to_vec()])
                .bind(),
        )
        .await
        .map_err(|_| failure("Endpoint creation timed out"))?
        .map_err(failure)?;
        if timeout(TIMEOUT, endpoint.online()).await.is_err() {
            endpoint.close().await;
            return Err(failure("No Iroh relay became available within 20 seconds"));
        }
        let inner = Rc::new(RefCell::new(Inner {
            endpoint: endpoint.clone(),
            callback: Some(callback),
            connection: None,
            generation: 0,
            pending: None,
            last_operation: 0,
            closed: false,
            sends: 0,
            send_bytes: 0,
            offers: BTreeMap::new(),
            offer_timer: None,
            operations: 0,
            next_offer: 0,
        }));
        let accept_shared = inner.clone();
        spawn_local(async move {
            while let Some(incoming) = endpoint.accept().await {
                let offer = {
                    let mut inner = accept_shared.borrow_mut();
                    if inner.closed || inner.offers.len() >= MAX_OFFERS {
                        incoming.refuse();
                        continue;
                    }
                    let Some(id) = inner.next_offer.checked_add(1) else {
                        incoming.refuse();
                        continue;
                    };
                    inner.next_offer = id;
                    inner.offers.insert(
                        id,
                        Offer {
                            incoming,
                            expires: Instant::now() + TIMEOUT,
                        },
                    );
                    id
                };
                emit(
                    &accept_shared,
                    Event {
                        offer: Some(offer),
                        ..Event::new("incoming")
                    },
                );
                expire_offers(&accept_shared);
            }
        });
        let me = inner.borrow().endpoint.id().to_string();
        emit(
            &inner,
            Event {
                peer: Some(&me),
                ..Event::new("ready")
            },
        );
        Ok(Self { inner })
    }

    #[wasm_bindgen(js_name = endpointId)]
    pub fn endpoint_id(&self) -> String {
        self.inner.borrow().endpoint.id().to_string()
    }

    pub fn invitation(&self) -> Result<String, JsValue> {
        if self.inner.borrow().closed {
            return Err(failure("Endpoint is closed"));
        }
        invitation(&self.inner.borrow().endpoint.addr()).map_err(failure)
    }

    pub async fn join(&self, invite: String, operation: u32) -> Result<(), JsValue> {
        let addr = parse_invitation(&invite).map_err(failure)?;
        let (endpoint, generation) = {
            let mut inner = self.inner.borrow_mut();
            if addr.id == inner.endpoint.id() {
                return Err(failure("An endpoint cannot join itself"));
            }
            let generation = begin(&mut inner, operation)?;
            (inner.endpoint.clone(), generation)
        };
        emit(
            &self.inner,
            Event {
                peer: Some(&addr.id.to_string()),
                operation: Some(operation),
                ..Event::new("connecting")
            },
        );
        let _operation = NativeOperation(self.inner.clone());
        let result = timeout(TIMEOUT, endpoint.connect(addr, ALPN))
            .await
            .map_err(|_| failure("Connection timed out"))
            .and_then(|result| result.map_err(failure));
        finish_connection(&self.inner, generation, operation, result).await
    }

    #[wasm_bindgen(js_name = acceptOffer)]
    pub async fn accept_offer(&self, offer: u32, operation: u32) -> Result<(), JsValue> {
        let (incoming, generation) = {
            let mut inner = self.inner.borrow_mut();
            let offer = inner
                .offers
                .remove(&offer)
                .ok_or_else(|| failure("Incoming offer is unavailable"))?;
            if offer.expires <= Instant::now() {
                offer.incoming.refuse();
                return Err(failure("Incoming offer expired"));
            }
            let incoming = offer.incoming;
            match begin(&mut inner, operation) {
                Ok(generation) => (incoming, generation),
                Err(error) => {
                    incoming.refuse();
                    return Err(error);
                }
            }
        };
        let _operation = NativeOperation(self.inner.clone());
        let result = timeout(TIMEOUT, incoming)
            .await
            .map_err(|_| failure("Incoming connection timed out"))
            .and_then(|result| result.map_err(failure));
        finish_connection(&self.inner, generation, operation, result).await
    }

    #[wasm_bindgen(js_name = refuseOffer)]
    pub fn refuse_offer(&self, offer: u32) {
        let incoming = self.inner.borrow_mut().offers.remove(&offer);
        if let Some(incoming) = incoming {
            incoming.incoming.refuse();
        }
    }

    pub async fn send(
        &self,
        bytes: Vec<u8>,
        confirm_delivery: bool,
        connection_id: u32,
    ) -> Result<(), JsValue> {
        if bytes.len() > MAX_MESSAGE {
            return Err(failure("Transport payload exceeds 1048576 bytes"));
        }
        let (connection, generation) = {
            let mut inner = self.inner.borrow_mut();
            if inner.closed {
                return Err(failure("Endpoint is closed"));
            }
            if inner.sends >= MAX_IN_FLIGHT
                || bytes.len() > MAX_PENDING_BYTES.saturating_sub(inner.send_bytes)
            {
                return Err(failure("Transport send queue is full"));
            }
            let peer = inner
                .connection
                .as_ref()
                .filter(|peer| peer.operation == connection_id)
                .ok_or_else(|| failure("Connection is no longer current"))?;
            let connection = peer.connection.clone();
            inner.sends += 1;
            inner.send_bytes += bytes.len();
            (connection, inner.generation)
        };
        let reservation = NativeWrite {
            shared: self.inner.clone(),
            bytes: bytes.len(),
        };
        let result = timeout(TIMEOUT, async {
            let mut stream = connection.open_uni().await.map_err(failure)?;
            stream.write_all(&bytes).await.map_err(failure)?;
            stream.finish().map_err(failure)?;
            if confirm_delivery && stream.stopped().await.map_err(failure)?.is_some() {
                return Err(failure("Peer rejected the transport frame"));
            }
            Ok::<(), JsValue>(())
        })
        .await;
        drop(reservation);
        if !current(&self.inner, generation) {
            return Err(failure("Connection changed while sending"));
        }
        match result {
            Err(_) => {
                connection.close(3u32.into(), b"Outgoing transport frame timed out");
                Err(failure("Transport send timed out"))
            }
            Ok(result) => result,
        }
    }

    #[wasm_bindgen(js_name = disconnectPeer)]
    pub fn disconnect_peer(&self, connection_id: Option<u32>) {
        let expected = connection_id.unwrap_or(0);
        let peer = {
            let mut inner = self.inner.borrow_mut();
            if inner.closed {
                return;
            }
            if expected != 0
                && inner.connection.as_ref().map(|peer| peer.operation) != Some(expected)
                && inner.pending != Some(expected)
            {
                return;
            }
            inner.generation += 1;
            inner.pending = None;
            inner.connection.take()
        };
        if let Some(peer) = peer {
            let id = peer.connection.remote_id().to_string();
            peer.connection
                .close(0u32.into(), b"Party connection closed");
            emit(
                &self.inner,
                Event {
                    peer: Some(&id),
                    connection: Some(peer.operation),
                    message: Some("Party connection closed"),
                    ..Event::new("disconnected")
                },
            );
        }
    }

    pub fn close(&self) {
        let (endpoint, connection, callback, offers, offer_timer) = {
            let mut inner = self.inner.borrow_mut();
            if inner.closed {
                return;
            }
            inner.closed = true;
            inner.pending = None;
            inner.generation += 1;
            (
                inner.endpoint.clone(),
                inner.connection.take(),
                inner.callback.take(),
                std::mem::take(&mut inner.offers),
                inner.offer_timer.take(),
            )
        };
        if let Some(timer) = offer_timer {
            timer.abort();
        }
        for (_, offer) in offers {
            offer.incoming.refuse();
        }
        if let Some(peer) = connection {
            peer.connection.close(0u32.into(), b"User disconnected");
        }
        if let Some(callback) = callback {
            emit_callback(&callback, Event::new("closed"));
        }
        spawn_local(async move {
            endpoint.close().await;
        });
    }
}

impl Drop for Transport {
    fn drop(&mut self) {
        self.close();
    }
}
