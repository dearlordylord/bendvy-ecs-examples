import { list, rows, number } from "./host-values.mts"
import { parseProfile } from "./profile.mts"
import type { Profile, Setup } from "./profile.mts"
import Core from "./dist/menu-progression.mjs"
import * as Catalog from "./content.mts"

type Amount = BendABI.MenuAmount.Amount
type Progress = BendABI.MenuProgression.Progress
type Stats = BendABI.MenuProgression.Stats
type Condition = BendABI.MenuProgression.Condition
type Kind = BendABI.MenuProgression.SelectionKind
type History = { usedWeapons: number[]; evolvedWeapons: number[] }
type RunResult = {
  runId: string
  character: number
  stage: number
  tick: number
  gold: number
  kills: number
  level: number
  phase: number
  revivalsUsed: number
  bossesKilled: number
  relicCollected: number
  weapons: number[]
  enemiesKilled: number[]
  usedWeapons: number[]
  evolvedWeapons: number[]
}
type CatalogCondition = { stat: string; value: number }
const KEY = "nightfall-survivors-v1"
const profileStores = new WeakMap<Profile, string | null>()
export function isolatedStreamProfile(source: Profile, persist = false): Profile {
  let profile = structuredClone(source)
  if (persist) {
    try {
      profile = parseProfile(JSON.parse(localStorage.getItem(`${KEY}-stream`) ?? "null"))
    } catch {}
  }
  profileStores.set(profile, persist ? `${KEY}-stream` : null)
  return profile
}

function amount(value: number): Amount {
  if (!Number.isFinite(value) || value < 0) throw new TypeError("Expected a nonnegative finite progression amount")
  const [mantissa = "0", exponent = "0"] = String(value).split("e")
  const [whole = "0", fraction = ""] = mantissa.split(".")
  const scale = fraction.length - Number(exponent)
  const numerator = (whole + fraction + (scale < 0 ? "0".repeat(-scale) : "")).replace(/^0+/, "") || "0"
  const denominator = scale > 0 ? "1" + "0".repeat(scale) : "1"
  return {
    $: "Amount",
    numerator: list(numerator.split("").reverse().map(Number)),
    denominator: list(denominator.split("").reverse().map(Number))
  }
}
// Round once to IEEE 754; separately converting the two limbs can change saved fractions.
function decodedAmount(value: Amount): number {
  const numerator = BigInt(rows(value.numerator).reverse().join("") || "0")
  const denominator = BigInt(rows(value.denominator).reverse().join("") || "1")
  if (numerator === 0n) return 0
  let exponent = numerator.toString(2).length - denominator.toString(2).length
  if (exponent >= 0 ? numerator < denominator << BigInt(exponent) : numerator << BigInt(-exponent) < denominator)
    exponent--
  if (exponent > 1023) return Infinity
  const unit = Math.max(exponent - 52, -1074)
  const n = unit < 0 ? numerator << BigInt(-unit) : numerator
  const d = unit > 0 ? denominator << BigInt(unit) : denominator
  const quotient = n / d,
    remainder = n % d
  const twice = remainder * 2n
  const rounded = quotient + (twice > d || (twice === d && quotient % 2n !== 0n) ? 1n : 0n)
  return Number(rounded) * 2 ** unit
}
function statsToCore(stats: Profile["stats"]): Stats {
  return {
    $: "Stats",
    kills: amount(stats.kills),
    totalgold: amount(stats.totalgold),
    survive: amount(stats.survive),
    wins: amount(stats.wins),
    evolutions: amount(stats.evolutions),
    levels: amount(stats.levels),
    characters: amount(stats.characters),
    stages: amount(stats.stages),
    weapons: amount(stats.weapons),
    revivals: amount(stats.revivals),
    bosskills: amount(stats.bosskills),
    characterwins: amount(stats.characterwins),
    relics: amount(stats.relics)
  }
}
function decodedStats(stats: Stats): Profile["stats"] {
  return {
    kills: decodedAmount(stats.kills),
    totalgold: decodedAmount(stats.totalgold),
    survive: decodedAmount(stats.survive),
    wins: decodedAmount(stats.wins),
    evolutions: decodedAmount(stats.evolutions),
    levels: decodedAmount(stats.levels),
    characters: decodedAmount(stats.characters),
    stages: decodedAmount(stats.stages),
    weapons: decodedAmount(stats.weapons),
    revivals: decodedAmount(stats.revivals),
    bosskills: decodedAmount(stats.bosskills),
    characterwins: decodedAmount(stats.characterwins),
    relics: decodedAmount(stats.relics)
  }
}
function progress(profile: Profile): Progress {
  return {
    $: "Progress",
    gold: amount(profile.gold),
    meta: list(profile.meta),
    characters: list(profile.characters),
    stages: list(profile.stages),
    achievements: list(profile.achievements),
    stats: statsToCore(profile.stats),
    collection: {
      $: "Collection",
      weapons: list(profile.collection.weapons),
      evolutions: list(profile.collection.evolutions),
      enemies: list(profile.collection.enemies)
    },
    stageRelics: list(profile.stageRelics),
    wonCharacters: list(profile.wonCharacters),
    recorded: list(profile.recorded)
  }
}
function decodedProgress(value: Progress): Omit<Profile, "version" | "settings"> {
  return {
    gold: decodedAmount(value.gold),
    meta: rows(value.meta),
    characters: rows(value.characters),
    stages: rows(value.stages),
    achievements: rows(value.achievements),
    stats: decodedStats(value.stats),
    collection: {
      weapons: rows(value.collection.weapons),
      evolutions: rows(value.collection.evolutions),
      enemies: rows(value.collection.enemies)
    },
    stageRelics: rows(value.stageRelics),
    wonCharacters: rows(value.wonCharacters),
    recorded: rows(value.recorded)
  }
}
function condition(value: CatalogCondition): Condition {
  const stat = statKind(value.stat)
  return { $: "Condition", stat, threshold: amount(value.value) }
}
function statKind(value: string): BendABI.MenuProgression.Stat {
  switch (value) {
    case "kills":
      return { $: "Kills" }
    case "totalgold":
      return { $: "TotalGold" }
    case "survive":
      return { $: "Survive" }
    case "wins":
      return { $: "Wins" }
    case "evolutions":
      return { $: "Evolutions" }
    case "levels":
      return { $: "Levels" }
    case "characters":
      return { $: "Characters" }
    case "stages":
      return { $: "Stages" }
    case "weapons":
      return { $: "Weapons" }
    case "revivals":
      return { $: "Revivals" }
    case "bosskills":
      return { $: "BossKills" }
    case "characterwins":
      return { $: "CharacterWins" }
    case "relics":
      return { $: "Relics" }
    default:
      throw new TypeError(`Unknown progression statistic: ${value}`)
  }
}
function optionalCondition(value: CatalogCondition | undefined): BendMaybe<Condition> {
  return value === undefined ? { $: "None" } : { $: "Some", value: condition(value) }
}
function kind(value: string): Kind {
  switch (value) {
    case "character":
      return { $: "Character" }
    case "stage":
      return { $: "Stage" }
    case "arcana":
      return { $: "Arcana" }
    case "mode":
      return { $: "Mode" }
    case "weapon":
      return { $: "Weapon" }
    default:
      throw new TypeError(`Unknown progression kind: ${value}`)
  }
}
function unlockEntry(value: {
  id: number
  cost: number
  condition?: CatalogCondition
}): BendABI.MenuProgression.UnlockEntry {
  return { $: "UnlockEntry", id: value.id, cost: amount(value.cost), condition: optionalCondition(value.condition) }
}
const catalog: BendABI.MenuProgression.Catalog = {
  $: "Catalog",
  characters: list(Catalog.CHARACTERS.map(unlockEntry)),
  stages: list(Catalog.STAGES.map(unlockEntry)),
  arcana: list(Catalog.ARCANA.map((value) => value.id)),
  modes: list(
    Catalog.RUN_MODES.map((value) => ({
      $: "ModeEntry",
      id: value.id,
      condition: optionalCondition("condition" in value ? value.condition : undefined)
    }))
  ),
  upgrades: list(
    Catalog.META_UPGRADES.map((value) => ({
      $: "Upgrade",
      id: value.id,
      costBase: value.costBase,
      maxLevel: value.maxLevel
    }))
  ),
  weapons: list(Catalog.WEAPONS.map((value) => value.id)),
  weaponUnlocks: list(
    Catalog.WEAPON_UNLOCKS.map((value) => ({
      $: "WeaponUnlock",
      id: value.id,
      condition: optionalCondition("condition" in value ? value.condition : undefined),
      stageRelic: "stageRelic" in value ? { $: "Some", value: value.stageRelic } : { $: "None" }
    }))
  ),
  achievements: list(
    Catalog.ACHIEVEMENTS.map((value) => ({
      $: "Achievement",
      id: value.id,
      conditions: list(
        Object.entries(value.conditions).map(([stat, threshold]) => condition({ stat, value: number(threshold) }))
      )
    }))
  )
}
export function freshProfile(): Profile {
  return {
    version: 1,
    ...decodedProgress(Core.fresh()),
    settings: { muted: false, volume: 0.35, reducedMotion: false, showDamage: true }
  }
}
export function loadProfile(): Profile {
  try {
    const profile = parseProfile(JSON.parse(localStorage.getItem(KEY) || "null"))
    return { ...profile, ...decodedProgress(Core.normalize(progress(profile), catalog)) }
  } catch {
    return freshProfile()
  }
}
export function saveProfile(profile: Profile): boolean {
  try {
    const store = profileStores.has(profile) ? profileStores.get(profile) : KEY
    if (store) localStorage.setItem(store, JSON.stringify(profile))
    return true
  } catch {
    return false
  }
}
export function upgradeStatus(profile: Profile, id: number) {
  const result = Core.upgrade_status(progress(profile), id, catalog)
  return {
    rank: result.rank,
    cost: result.cost.$ === "None" ? Infinity : decodedAmount(result.cost.value),
    maxed: result.maxed,
    canBuy: result.canBuy
  }
}
export function purchaseStatus(profile: Profile, value: string, id: number) {
  const result = Core.purchase_status(progress(profile), kind(value), id, catalog)
  return {
    owned: result.owned,
    eligible: result.eligible,
    affordable: result.affordable,
    canBuy: result.canBuy,
    missingGold: decodedAmount(result.missingGold),
    cost: result.cost.$ === "None" ? 0 : decodedAmount(result.cost.value)
  }
}
export function validateSetup(profile: Profile, setup: Partial<Setup>): Setup {
  const result = Core.validate_setup(
    progress(profile),
    {
      $: "Setup",
      character: setup.character ?? 0,
      stage: setup.stage ?? 0,
      arcana: setup.arcana ?? 0,
      mode: setup.mode ?? 0
    },
    catalog
  )
  return { character: result.character, stage: result.stage, arcana: result.arcana, mode: result.mode }
}
function apply(profile: Profile, outcome: BendMaybe<Progress>): boolean {
  if (outcome.$ === "None") return false
  Object.assign(profile, decodedProgress(outcome.value))
  saveProfile(profile)
  return true
}
export function buyUpgrade(profile: Profile, id: number): boolean {
  return apply(profile, Core.buy_upgrade(progress(profile), id, catalog))
}
export const metaCode = (profile: Profile) => Core.meta_code(progress(profile))
export const requirementsMet = (profile: Profile, item: { condition?: CatalogCondition }) =>
  Core.requirements_met(progress(profile), optionalCondition(item.condition))
export const allowedWeapons = (profile: Profile) => Core.allowed_weapons(progress(profile), catalog)
export const isUnlocked = (profile: Profile, value: string, id: number) =>
  Core.unlocked(progress(profile), kind(value), id, catalog)
export function unlock(profile: Profile, value: string, id: number): boolean {
  return apply(profile, Core.purchase(progress(profile), kind(value), id, catalog))
}
export function observeRun(history: Partial<History>, frame: { weapons?: number[] }): History {
  const result = Core.observe_run(
    { $: "History", usedWeapons: list(history.usedWeapons ?? []), evolvedWeapons: list(history.evolvedWeapons ?? []) },
    list(frame.weapons ?? [])
  )
  return { usedWeapons: rows(result.usedWeapons), evolvedWeapons: rows(result.evolvedWeapons) }
}
export function recordRun(profile: Profile, frame: RunResult): string[] {
  const receipt: BendABI.MenuProgression.RunReceipt = {
    $: "RunReceipt",
    runId: frame.runId,
    character: frame.character,
    stage: frame.stage,
    tick: frame.tick,
    gold: amount(frame.gold),
    kills: amount(frame.kills),
    level: amount(frame.level),
    phase: frame.phase,
    revivalsUsed: amount(frame.revivalsUsed),
    bossesKilled: amount(frame.bossesKilled),
    relicCollected: frame.relicCollected === 1,
    weapons: list(frame.weapons),
    enemiesKilled: list(frame.enemiesKilled),
    history: { $: "History", usedWeapons: list(frame.usedWeapons), evolvedWeapons: list(frame.evolvedWeapons) }
  }
  const result = Core.record_run(progress(profile), receipt, catalog)
  Object.assign(profile, decodedProgress(result.profile))
  saveProfile(profile)
  return rows(result.added)
}
