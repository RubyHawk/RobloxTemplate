--!strict

local StageTypes = {}

export type JsonScalar = string | number | boolean
export type JsonValue = JsonScalar | { JsonValue } | { [string]: JsonValue }

export type Vec3 = {
	x: number,
	y: number,
	z: number,
}

export type BuildPolicy = "Allowed" | "Blocked" | "AutoOnly"
export type EnemyTraversalPolicy = "Allowed" | "Blocked"
export type PathNodeKind = "Spawn" | "Junction" | "Goal"

export type CellOverride = {
	terrainId: string?,
	buildPolicy: BuildPolicy?,
	enemyTraversalPolicy: EnemyTraversalPolicy?,
	roles: { [string]: boolean }?,
	metadata: { [string]: JsonValue }?,
}

export type GridDefinition = {
	columns: number,
	rows: number,
	cellSize: number,
	defaultCell: CellOverride,
	cells: { [string]: CellOverride },
}

export type PathNode = {
	id: string,
	name: string,
	kind: PathNodeKind,
	position: Vec3,
	tags: { string },
}

export type WaveRangePredicate = {
	kind: "WaveRange",
	minimum: number?,
	maximum: number?,
}

export type StageFlagPredicate = {
	kind: "StageFlagEquals",
	key: string,
	value: boolean,
}

export type EnemyTagPredicate = {
	kind: "EnemyTag",
	tag: string,
}

export type VisitCountPredicate = {
	kind: "VisitCountBelow",
	nodeId: string,
	maximum: number,
}

export type StageUnlockedPredicate = {
	kind: "StageUnlocked",
	stageId: string,
}

export type UpgradeLevelPredicate = {
	kind: "UpgradeLevelAtLeast",
	upgradeId: string,
	level: number,
}

export type CurrencyPredicate = {
	kind: "CurrencyAtLeast",
	currencyId: string,
	amount: number,
}

export type RoutePredicate =
	WaveRangePredicate
	| StageFlagPredicate
	| EnemyTagPredicate
	| VisitCountPredicate
	| StageUnlockedPredicate
	| UpgradeLevelPredicate
	| CurrencyPredicate

export type PathEdge = {
	id: string,
	fromNodeId: string,
	toNodeId: string,
	outHandleOffset: Vec3,
	inHandleOffset: Vec3,
	laneProfileId: string,
	priority: number,
	predicates: { RoutePredicate },
	metadata: { [string]: JsonValue }?,
}

export type LaneProfile = {
	id: string,
	offsets: { number },
	clearanceRadius: number,
}

export type PathGraphDefinition = {
	id: string,
	name: string,
	nodes: { [string]: PathNode },
	edges: { [string]: PathEdge },
	outgoingEdgeIds: { [string]: { string } }?,
	laneProfiles: { [string]: LaneProfile },
	maxNodeVisitsPerEnemy: number,
	maxTravelDistance: number,
}

export type StageUnlockPredicate = StageUnlockedPredicate | UpgradeLevelPredicate | CurrencyPredicate

export type EnemyTint = {
	r: number,
	g: number,
	b: number,
}

-- Animation overrides for an enemy rig. An empty id means "use whatever the rig
-- model declares under its own Animations folder", so a character asset that
-- ships with animations needs no authoring at all.
export type EnemyAnimations = {
	walkId: string,
	deathId: string,
}

export type EnemyTypeDefinition = {
	id: string,
	name: string,
	tags: { string },
	health: number,
	speed: number,
	reward: number,
	baseDamage: number,
	modelId: string,
	renderScale: number,
	tint: EnemyTint?,
	animations: EnemyAnimations?,
}

export type WaveEntryDefinition = {
	enemyTypeId: string,
	count: number,
	spacingSeconds: number,
	startDelaySeconds: number,
	healthScale: number?,
	rewardScale: number?,
	speedScale: number?,
}

export type WaveDefinition = {
	entries: { WaveEntryDefinition },
	isBoss: boolean?,
}

-- Growth applied once per completed loop of the authored waves. Linear adds
-- `rate * loops`; Exponential compounds `(1 + rate) ^ loops`. Spacing is the one
-- inverted axis: its rate tightens the gap between spawns instead of widening
-- it, so every rate reads as "more difficulty" at higher values.
export type WaveLoopCurve = "Linear" | "Exponential"

export type WaveLoopScaling = {
	curve: WaveLoopCurve,
	healthPerLoop: number,
	rewardPerLoop: number,
	speedPerLoop: number,
	countPerLoop: number,
	spacingPerLoop: number,
	bossEveryWaves: number,
}

-- `endless` and `loopScaling` are optional at runtime because generated bundles
-- predating schema 6 do not carry them; TowerDefenseWaves resolves the fallback.
export type WaveSetDefinition = {
	id: string,
	name: string,
	waves: { WaveDefinition },
	endless: boolean?,
	loopScaling: WaveLoopScaling?,
}

export type MapDefinition = {
	id: string,
	name: string,
	displayOrder: number,
	backdropImageId: string,
	metadata: { [string]: JsonValue },
}

export type StageDefinition = {
	schemaVersion: number,
	id: string,
	mapId: string,
	stageGroupId: string,
	stageNumber: number,
	levelNumber: number,
	name: string,
	displayOrder: number,
	grid: GridDefinition,
	pathGraphs: { [string]: PathGraphDefinition },
	waveSetId: string,
	themeId: string,
	modifierIds: { string },
	unlockRequirements: { StageUnlockPredicate },
	metadata: { [string]: JsonValue },
}

export type StageProject = {
	schemaVersion: number,
	startingStageId: string,
	selectedStageId: string?,
	maps: { [string]: MapDefinition },
	stages: { [string]: StageDefinition },
	enemyTypes: { [string]: EnemyTypeDefinition },
	waveSets: { [string]: WaveSetDefinition },
	metadata: { [string]: JsonValue }?,
}

export type BakedPathSample = {
	position: Vec3,
	tangent: Vec3,
	up: Vec3,
	distance: number,
}

export type BakedPathEdge = PathEdge & {
	length: number,
	samples: { BakedPathSample },
}

export type RuntimePathGraph = {
	id: string,
	name: string,
	nodes: { [string]: PathNode },
	edges: { [string]: BakedPathEdge },
	outgoingEdgeIds: { [string]: { string } },
	laneProfiles: { [string]: LaneProfile },
	maxNodeVisitsPerEnemy: number,
	maxTravelDistance: number,
}

-- Editor previews use baked route geometry and a no-build mask, but they are
-- intentionally not checksum-addressed runtime artifacts.
export type StagePreviewDefinition = StageDefinition & {
	pathGraphs: { [string]: RuntimePathGraph },
	routeNoBuildMask: { [string]: boolean },
	routePreviewSignature: string?,
}

export type RuntimeStageDefinition = {
	schemaVersion: number,
	id: string,
	mapId: string,
	stageGroupId: string,
	stageNumber: number,
	levelNumber: number,
	name: string,
	displayOrder: number,
	grid: GridDefinition,
	pathGraphs: { [string]: RuntimePathGraph },
	waveSetId: string,
	themeId: string,
	modifierIds: { string },
	unlockRequirements: { StageUnlockPredicate },
	metadata: { [string]: JsonValue },
	routeNoBuildMask: { [string]: boolean },
	checksum: string,
}

export type RuntimeMapDefinition = {
	id: string,
	name: string,
	displayOrder: number,
	metadata: { [string]: JsonValue },
}

export type RuntimeStageBundle = {
	schemaVersion: number,
	sourceSchemaVersion: number,
	startingStageId: string,
	mapOrder: { string },
	maps: { [string]: RuntimeMapDefinition },
	stageOrder: { string },
	stages: { [string]: RuntimeStageDefinition },
	enemyTypeOrder: { string },
	enemyTypes: { [string]: EnemyTypeDefinition },
	waveSetOrder: { string },
	waveSets: { [string]: WaveSetDefinition },
	checksum: string,
}

export type ValidationSeverity = "Error" | "Warning"
export type ValidationIssue = {
	severity: ValidationSeverity,
	code: string,
	message: string,
	mapId: string?,
	stageId: string?,
	graphId: string?,
	objectId: string?,
}

return StageTypes
