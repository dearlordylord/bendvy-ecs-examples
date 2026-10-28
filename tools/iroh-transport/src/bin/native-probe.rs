//! Transport-only peer for browser/native interoperability. It does not interpret Bend packets.
use bendvy_iroh_transport::{ALPN, MAX_MESSAGE, invitation, parse_invitation};
use iroh::{Endpoint, RelayMode, RelayUrl, endpoint::presets};
use std::{io::Read, time::Duration};

async fn fault_peer(mode: &str) -> Result<(), Box<dyn std::error::Error>> {
    if !matches!(mode, "oversized" | "stalled") {
        return Err("Expected oversized or stalled fault mode".into());
    }
    let mut ticket = String::new();
    std::io::stdin().read_to_string(&mut ticket)?;
    let address = parse_invitation(ticket.trim())?;
    let relay: RelayUrl = "https://quint-graph.fly.dev".parse()?;
    let endpoint = Endpoint::builder(presets::N0)
        .relay_mode(RelayMode::Custom([relay].into_iter().collect()))
        .alpns(vec![ALPN.to_vec()])
        .bind()
        .await?;
    tokio::time::timeout(Duration::from_secs(30), endpoint.online()).await?;
    let connection =
        tokio::time::timeout(Duration::from_secs(25), endpoint.connect(address, ALPN)).await??;
    let mut stream = connection.open_uni().await?;
    match mode {
        "oversized" => {
            let _ = stream.write_all(&vec![7; MAX_MESSAGE + 1]).await;
            let _ = stream.finish();
        }
        "stalled" => stream.write_all(&[7]).await?,
        _ => unreachable!(),
    }
    println!("READY raw {mode} frame written");
    tokio::time::timeout(Duration::from_secs(25), connection.closed()).await?;
    endpoint.close().await;
    println!("PASS raw {mode} frame rejected by remote transport");
    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    if std::env::args().nth(1).as_deref() == Some("--fault") {
        return fault_peer(&std::env::args().nth(2).ok_or("Missing fault mode")?).await;
    }
    let endpoint = Endpoint::builder(presets::N0)
        .alpns(vec![ALPN.to_vec()])
        .bind()
        .await?;
    tokio::time::timeout(std::time::Duration::from_secs(30), endpoint.online()).await?;
    println!("{}", invitation(&endpoint.addr())?);
    let connection = if let Some(invite) = std::env::args().nth(1) {
        endpoint.connect(parse_invitation(&invite)?, ALPN).await?
    } else {
        endpoint.accept().await.ok_or("Endpoint closed")?.await?
    };
    println!("CONNECTED {}", connection.remote_id());
    println!("PATHS {:?}", connection.paths());
    loop {
        let mut incoming = match connection.accept_uni().await {
            Ok(stream) => stream,
            Err(_) => break,
        };
        let bytes = incoming.read_to_end(MAX_MESSAGE).await?;
        let mut outgoing = connection.open_uni().await?;
        outgoing.write_all(&bytes).await?;
        outgoing.finish()?;
        println!("ECHO {} bytes", bytes.len());
    }
    endpoint.close().await;
    Ok(())
}
