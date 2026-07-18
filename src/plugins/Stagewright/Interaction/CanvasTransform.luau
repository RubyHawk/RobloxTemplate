--!strict

local CanvasTransform = {}

export type Point2 = {
	x: number,
	y: number,
}

export type Transform = {
	viewportSize: Point2,
	worldSize: Point2,
	padding: number,
	fitCenter: Point2,
	center: Point2,
	zoom: number,
}

CanvasTransform.MIN_ZOOM = 0.25
CanvasTransform.MAX_ZOOM = 8

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function assertFinite(value: number, label: string)
	assert(isFinite(value), `{label} must be finite`)
end

local function assertPoint(point: Point2, label: string)
	assertFinite(point.x, `{label}.x`)
	assertFinite(point.y, `{label}.y`)
end

local function frozenPoint(x: number, y: number): Point2
	return table.freeze({
		x = x,
		y = y,
	})
end

local function frozenTransform(
	viewportSize: Point2,
	worldSize: Point2,
	padding: number,
	fitCenter: Point2,
	center: Point2,
	zoom: number
): Transform
	return table.freeze({
		viewportSize = frozenPoint(viewportSize.x, viewportSize.y),
		worldSize = frozenPoint(worldSize.x, worldSize.y),
		padding = padding,
		fitCenter = frozenPoint(fitCenter.x, fitCenter.y),
		center = frozenPoint(center.x, center.y),
		zoom = zoom,
	})
end

local function validateDimensions(viewportSize: Point2, worldSize: Point2, padding: number)
	assertPoint(viewportSize, "viewportSize")
	assertPoint(worldSize, "worldSize")
	assertFinite(padding, "padding")
	assert(viewportSize.x > 0 and viewportSize.y > 0, "viewportSize must be positive")
	assert(worldSize.x > 0 and worldSize.y > 0, "worldSize must be positive")
	assert(padding >= 0, "padding cannot be negative")
	assert(
		viewportSize.x > padding * 2 and viewportSize.y > padding * 2,
		"padding must leave a positive viewport area"
	)
end

local function fitScale(transform: Transform): number
	local availableWidth = transform.viewportSize.x - transform.padding * 2
	local availableHeight = transform.viewportSize.y - transform.padding * 2
	return math.min(availableWidth / transform.worldSize.x, availableHeight / transform.worldSize.y)
end

function CanvasTransform.fit(
	viewportSize: Point2,
	worldSize: Point2,
	padding: number?,
	fitCenter: Point2?
): Transform
	local resolvedPadding = padding or 0
	local resolvedFitCenter = fitCenter or { x = 0, y = 0 }
	validateDimensions(viewportSize, worldSize, resolvedPadding)
	assertPoint(resolvedFitCenter, "fitCenter")
	return frozenTransform(viewportSize, worldSize, resolvedPadding, resolvedFitCenter, resolvedFitCenter, 1)
end

function CanvasTransform.scale(transform: Transform): number
	return fitScale(transform) * transform.zoom
end

function CanvasTransform.worldToCanvas(transform: Transform, worldPoint: Point2): Point2
	assertPoint(worldPoint, "worldPoint")
	local scale = CanvasTransform.scale(transform)
	return {
		x = transform.viewportSize.x * 0.5 + (worldPoint.x - transform.center.x) * scale,
		y = transform.viewportSize.y * 0.5 + (worldPoint.y - transform.center.y) * scale,
	}
end

function CanvasTransform.canvasToWorld(transform: Transform, canvasPoint: Point2): Point2
	assertPoint(canvasPoint, "canvasPoint")
	local scale = CanvasTransform.scale(transform)
	return {
		x = transform.center.x + (canvasPoint.x - transform.viewportSize.x * 0.5) / scale,
		y = transform.center.y + (canvasPoint.y - transform.viewportSize.y * 0.5) / scale,
	}
end

function CanvasTransform.pan(transform: Transform, canvasDelta: Point2): Transform
	assertPoint(canvasDelta, "canvasDelta")
	local scale = CanvasTransform.scale(transform)
	return frozenTransform(
		transform.viewportSize,
		transform.worldSize,
		transform.padding,
		transform.fitCenter,
		{
			x = transform.center.x - canvasDelta.x / scale,
			y = transform.center.y - canvasDelta.y / scale,
		},
		transform.zoom
	)
end

function CanvasTransform.setZoomAt(transform: Transform, zoom: number, canvasAnchor: Point2): Transform
	assertFinite(zoom, "zoom")
	assert(zoom > 0, "zoom must be positive")
	assertPoint(canvasAnchor, "canvasAnchor")
	local resolvedZoom = math.clamp(zoom, CanvasTransform.MIN_ZOOM, CanvasTransform.MAX_ZOOM)
	if resolvedZoom == transform.zoom then
		return transform
	end

	local anchoredWorldPoint = CanvasTransform.canvasToWorld(transform, canvasAnchor)
	local newScale = fitScale(transform) * resolvedZoom
	local viewportCenterX = transform.viewportSize.x * 0.5
	local viewportCenterY = transform.viewportSize.y * 0.5
	return frozenTransform(
		transform.viewportSize,
		transform.worldSize,
		transform.padding,
		transform.fitCenter,
		{
			x = anchoredWorldPoint.x - (canvasAnchor.x - viewportCenterX) / newScale,
			y = anchoredWorldPoint.y - (canvasAnchor.y - viewportCenterY) / newScale,
		},
		resolvedZoom
	)
end

function CanvasTransform.zoomAt(transform: Transform, factor: number, canvasAnchor: Point2): Transform
	assertFinite(factor, "factor")
	assert(factor > 0, "factor must be positive")
	return CanvasTransform.setZoomAt(transform, transform.zoom * factor, canvasAnchor)
end

function CanvasTransform.resize(transform: Transform, viewportSize: Point2): Transform
	validateDimensions(viewportSize, transform.worldSize, transform.padding)
	return frozenTransform(
		viewportSize,
		transform.worldSize,
		transform.padding,
		transform.fitCenter,
		transform.center,
		transform.zoom
	)
end

function CanvasTransform.resetFit(transform: Transform): Transform
	return frozenTransform(
		transform.viewportSize,
		transform.worldSize,
		transform.padding,
		transform.fitCenter,
		transform.fitCenter,
		1
	)
end

return table.freeze(CanvasTransform)
