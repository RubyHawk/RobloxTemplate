import fs from "node:fs";
import path from "node:path";

const [, , command, ...args] = process.argv;

function option(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function options(name) {
  const values = [];
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === name && args[index + 1]) values.push(args[index + 1]);
  }
  return values;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function stringifyCompact(value) {
  if (Array.isArray(value)) return `[${value.map(stringifyCompact).join(", ")}]`;
  if (value && typeof value === "object") {
    return `{${Object.entries(value)
      .map(([key, child]) => `${JSON.stringify(key)}: ${stringifyCompact(child)}`)
      .join(", ")}}`;
  }
  return JSON.stringify(value);
}

function canInlinePretty(value) {
  const compact = stringifyCompact(value);
  if (compact.length > 160) return false;
  if (Array.isArray(value)) {
    return value.length === 0
      || value.every((child) =>
        child === null
        || typeof child !== "object"
        || (Array.isArray(child) && child.every((item) => item === null || typeof item !== "object"))
        || (
          !Array.isArray(child)
          && !Object.hasOwn(child, "Children")
          && !Object.hasOwn(child, "Properties")
          && stringifyCompact(child).length <= 100
        )
      );
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value);
    return entries.length <= 4
      && !Object.hasOwn(value, "Children")
      && !Object.hasOwn(value, "Properties")
      && entries.every(([, child]) =>
        child === null
        || typeof child !== "object"
        || (Array.isArray(child) && canInlinePretty(child))
      );
  }
  return true;
}

function stringifyPretty(value, depth = 0) {
  if (canInlinePretty(value)) return stringifyCompact(value);
  const indent = "  ".repeat(depth);
  const childIndent = "  ".repeat(depth + 1);
  if (Array.isArray(value)) {
    return `[\n${value.map((child) => `${childIndent}${stringifyPretty(child, depth + 1)}`).join(",\n")}\n${indent}]`;
  }
  if (value && typeof value === "object") {
    return `{\n${Object.entries(value)
      .map(([key, child]) => `${childIndent}${JSON.stringify(key)}: ${stringifyPretty(child, depth + 1)}`)
      .join(",\n")}\n${indent}}`;
  }
  return JSON.stringify(value);
}

function writeJson(file, value, pretty = false) {
  fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
  const serialized = pretty ? stringifyPretty(value) : stringifyCompact(value);
  fs.writeFileSync(file, `${serialized}\n`, "utf8");
}

function childrenOf(node) {
  return Array.isArray(node?.Children) ? node.Children : [];
}

const SOURCE_ONLY_UI_CLASSES = new Set([
  "UIAspectRatioConstraint",
  "UICorner",
  "UIGradient",
  "UIGridLayout",
  "UIListLayout",
  "UIPadding",
  "UIScale",
  "UISizeConstraint",
  "UIStroke"
]);

const FIGMA_VISUAL_CLASSES = new Set([
  "Frame",
  "CanvasGroup",
  "ImageButton",
  "ImageLabel",
  "ScrollingFrame",
  "TextBox",
  "TextButton",
  "TextLabel",
  "VideoFrame",
  "ViewportFrame"
]);

function indexNamedNodes(model, rootName) {
  const byPath = new Map();
  const duplicates = new Set();
  const visit = (node, currentPath) => {
    if (node?.Name) {
      if (byPath.has(currentPath)) duplicates.add(currentPath);
      byPath.set(currentPath, node);
    }
    for (const child of childrenOf(node)) {
      if (child?.Name) visit(child, `${currentPath}/${child.Name}`);
    }
  };

  const root = childrenOf(model).find((child) => child.Name === "Root");
  if (root) visit(root, `${rootName}/Root`);
  else {
    for (const child of childrenOf(model)) if (child?.Name) visit(child, `${rootName}/${child.Name}`);
  }
  return { byPath, duplicates };
}

function pruneToAuthoritativeEntries(model, rootName, entriesByPath) {
  const authoritativePaths = new Set(
    [...entriesByPath.keys()].filter((entryPath) => entryPath.startsWith(`${rootName}/`))
  );

  const hasAuthoritativeDescendant = (candidatePath) => {
    const prefix = `${candidatePath}/`;
    for (const entryPath of authoritativePaths) {
      if (entryPath.startsWith(prefix)) return true;
    }
    return false;
  };

  const removedPaths = [];
  const containsFigmaVisual = (node) =>
    FIGMA_VISUAL_CLASSES.has(node?.ClassName)
    || childrenOf(node).some((child) => containsFigmaVisual(child));
  const pruneChildren = (node, nodePath) => {
    const keptChildren = [];
    for (const child of childrenOf(node)) {
      const childName = typeof child?.Name === "string" && child.Name.trim()
        ? child.Name
        : "";
      const childPath = childName ? `${nodePath}/${childName}` : nodePath;
      const isMapped = childName && authoritativePaths.has(childPath);
      const isMappedAncestor = childName && hasAuthoritativeDescendant(childPath);
      const isSourceOnlyImplementation = SOURCE_ONLY_UI_CLASSES.has(child?.ClassName)
        || (
          !FIGMA_VISUAL_CLASSES.has(child?.ClassName)
          && !containsFigmaVisual(child)
        );
      const keep = !childName || isMapped || isMappedAncestor || isSourceOnlyImplementation;

      if (!keep) {
        removedPaths.push(childPath);
        continue;
      }
      pruneChildren(child, childPath);
      keptChildren.push(child);
    }
    node.Children = keptChildren;
  };

  const root = childrenOf(model).find((child) => child.Name === "Root");
  if (root) {
    pruneChildren(root, `${rootName}/Root`);
  } else {
    pruneChildren(model, rootName);
  }
  return removedPaths;
}

function ensureProperties(node) {
  node.Properties ||= {};
  return node.Properties;
}

function effectChild(node, className) {
  return childrenOf(node).find((child) => child.ClassName === className);
}

function ensureEffectChild(node, className) {
  const existing = effectChild(node, className);
  if (existing) return existing;
  const created = { ClassName: className, Properties: {}, Children: [] };
  node.Children ||= [];
  node.Children.push(created);
  return created;
}

function removeEffectChildren(node, className, predicate = () => true) {
  node.Children = childrenOf(node).filter(
    (child) => child.ClassName !== className || !predicate(child)
  );
}

function strokeMode(stroke) {
  return String(stroke?.Properties?.ApplyStrokeMode || "");
}

function ensureStrokeChild(node, mode) {
  const existing = childrenOf(node).find(
    (child) => child.ClassName === "UIStroke"
      && (
        strokeMode(child) === mode
        || (mode === "Border" && strokeMode(child) === "")
      )
  );
  if (existing) return existing;
  const created = {
    ClassName: "UIStroke",
    Properties: mode ? { ApplyStrokeMode: mode } : {},
    Children: []
  };
  node.Children ||= [];
  node.Children.push(created);
  return created;
}

function sequenceKeypoints(keypoints, type) {
  if (!Array.isArray(keypoints) || keypoints.length === 0) return null;
  const normalized = keypoints
    .map((keypoint) => {
      const time = Math.max(0, Math.min(1, Number(keypoint?.time) || 0));
      if (type === "color") {
        if (!Array.isArray(keypoint?.color) || keypoint.color.length < 3) return null;
        return { time, color: keypoint.color.slice(0, 3).map((channel) => Math.max(0, Math.min(1, Number(channel) || 0))) };
      }
      return { time, value: Math.max(0, Math.min(1, Number(keypoint?.value) || 0)), envelope: 0 };
    })
    .filter(Boolean)
    .sort((left, right) => left.time - right.time);
  if (!normalized.length) return null;
  if (normalized.length === 1) {
    const only = normalized[0];
    normalized.unshift({ ...only, time: 0 });
    normalized.push({ ...only, time: 1 });
  } else {
    if (normalized[0].time > 0) normalized.unshift({ ...normalized[0], time: 0 });
    if (normalized.at(-1).time < 1) normalized.push({ ...normalized.at(-1), time: 1 });
  }
  return normalized;
}

function applyGradient(node, entry) {
  if (!Object.prototype.hasOwnProperty.call(entry, "gradient")) return;
  if (!entry.gradient) {
    removeEffectChildren(node, "UIGradient");
    return;
  }
  if (entry.gradient.type !== "linear") {
    fail(`Unsupported Figma gradient type at ${entry.path}: ${entry.gradient.type || "<missing>"}`);
  }
  const colorPoints = sequenceKeypoints(entry.gradient.colorKeypoints, "color");
  const transparencyPoints = sequenceKeypoints(entry.gradient.transparencyKeypoints, "number");
  if (!colorPoints || !transparencyPoints) {
    fail(`Incomplete linear gradient at ${entry.path}.`);
  }
  const gradient = ensureEffectChild(node, "UIGradient");
  const props = ensureProperties(gradient);
  props.Color = { ColorSequence: { keypoints: colorPoints } };
  props.Transparency = { NumberSequence: { keypoints: transparencyPoints } };
  props.Rotation = Number.isFinite(Number(entry.gradient.rotation))
    ? Number(entry.gradient.rotation)
    : 0;
  props.Enabled = true;

  if (String(node.ClassName).startsWith("Text")) {
    const nodeProps = ensureProperties(node);
    nodeProps.TextColor3 = [1, 1, 1];
    nodeProps.TextTransparency = 0;
  } else if (String(node.ClassName).startsWith("Image")) {
    const nodeProps = ensureProperties(node);
    nodeProps.ImageColor3 = [1, 1, 1];
    nodeProps.ImageTransparency = 0;
  } else {
    const nodeProps = ensureProperties(node);
    nodeProps.BackgroundColor3 = [1, 1, 1];
    nodeProps.BackgroundTransparency = 0;
  }
}

function applyStroke(node, entry) {
  const isText = String(node.ClassName).startsWith("Text");
  const ownsBorderStroke = Object.prototype.hasOwnProperty.call(entry, "stroke");
  if (ownsBorderStroke && entry.stroke?.color) {
    const mode = isText ? "Border" : "";
    const stroke = ensureStrokeChild(node, mode);
    const strokeProps = ensureProperties(stroke);
    if (mode) strokeProps.ApplyStrokeMode = mode;
    strokeProps.Color = entry.stroke.color.map(Number);
    strokeProps.Transparency = 1 - Math.max(0, Math.min(1, Number(entry.stroke.opacity ?? 1)));
    if (Number.isFinite(entry.stroke.thickness)) strokeProps.Thickness = Number(entry.stroke.thickness);
  } else if (ownsBorderStroke) {
    removeEffectChildren(node, "UIStroke", (stroke) =>
      !isText || strokeMode(stroke) !== "Contextual"
    );
  }

  if (!isText) return;
  const props = ensureProperties(node);
  const ownsTextStroke = Object.prototype.hasOwnProperty.call(entry, "textStroke");
  if (ownsTextStroke && entry.textStroke?.color) {
    const stroke = ensureStrokeChild(node, "Contextual");
    const strokeProps = ensureProperties(stroke);
    strokeProps.ApplyStrokeMode = "Contextual";
    strokeProps.Color = entry.textStroke.color.map(Number);
    strokeProps.Transparency = 1 - Math.max(0, Math.min(1, Number(entry.textStroke.opacity ?? 1)));
    if (Number.isFinite(entry.textStroke.thickness)) {
      strokeProps.Thickness = Number(entry.textStroke.thickness);
    }
    props.TextStrokeColor3 = entry.textStroke.color.map(Number);
    props.TextStrokeTransparency = 1;
  } else if (ownsTextStroke) {
    removeEffectChildren(node, "UIStroke", (stroke) => strokeMode(stroke) === "Contextual");
    props.TextStrokeTransparency = 1;
  }
}

function setUdim2(props, key, sx, ox, sy, oy) {
  props[key] = { UDim2: [[sx, Math.round(ox)], [sy, Math.round(oy)]] };
}

function parentPath(nodePath) {
  const slash = String(nodePath || "").lastIndexOf("/");
  return slash > 0 ? nodePath.slice(0, slash) : "";
}

function finiteOr(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

// Imported Figma nodes retain the original Roblox scale/offset metadata. Once
// a designer substantially resizes a stretch-based node in Figma (for example,
// turning a full-width header into a 280 px title tab), blindly retaining the
// old scale produces values such as UDim2.fromScale(1, 0) + -1158 px. It looks
// correct only at the 1600x900 authoring viewport and collapses on phones.
//
// Keep scale semantics for small edits, but rebase an axis to fixed size when
// the edited proportion is materially different from the authored scale.
function rebasedSizeScale(authoredScale, actualSize, parentSize) {
  if (!Number.isFinite(parentSize) || parentSize <= 0) return authoredScale;
  if (Math.abs(authoredScale) < 0.001) return 0;
  const actualRatio = actualSize / parentSize;
  return Math.abs(actualRatio - authoredScale) > 0.45 ? 0 : authoredScale;
}

function rebasedPosition(authoredScale, authoredAnchor, sizeScale, start, size, parentSize) {
  if (Math.abs(sizeScale) >= 0.001) {
    return { scale: authoredScale, anchor: authoredAnchor };
  }
  const leading = start;
  const trailing = parentSize - (start + size);
  const centerOffset = start + size * 0.5 - parentSize * 0.5;
  const edgeThreshold = Math.max(40, parentSize * 0.1);
  const centerThreshold = Math.max(24, parentSize * 0.08);
  if (leading <= edgeThreshold && trailing > leading + centerThreshold) {
    return { scale: 0, anchor: 0 };
  }
  if (trailing <= edgeThreshold && leading > trailing + centerThreshold) {
    return { scale: 1, anchor: 1 };
  }
  if (Math.abs(centerOffset) <= centerThreshold) {
    return { scale: 0.5, anchor: 0.5 };
  }
  return { scale: authoredScale, anchor: authoredAnchor };
}

function entryGeometry(entry, entriesByPath) {
  const layout = entry.layout;
  const parentEntry = entriesByPath?.get(parentPath(entry.path));
  const parentWidth = finiteOr(parentEntry?.width, finiteOr(layout?.parentWidth, 1600));
  const parentHeight = finiteOr(parentEntry?.height, finiteOr(layout?.parentHeight, 900));
  const originalWidth = parentWidth * finiteOr(layout?.size?.sx, 0) + finiteOr(layout?.size?.ox, 0);
  const originalHeight = parentHeight * finiteOr(layout?.size?.sy, 0) + finiteOr(layout?.size?.oy, 0);
  const useOriginalWidth = Number(entry.width) <= 1 && originalWidth > 1;
  const useOriginalHeight = Number(entry.height) <= 1 && originalHeight > 1;
  const width = Math.max(1, useOriginalWidth ? originalWidth : finiteOr(entry.width, 1));
  const height = Math.max(1, useOriginalHeight ? originalHeight : finiteOr(entry.height, 1));
  const anchorX = finiteOr(layout?.anchor?.x, 0);
  const anchorY = finiteOr(layout?.anchor?.y, 0);
  const x = useOriginalWidth
    ? parentWidth * finiteOr(layout?.pos?.sx, 0) + finiteOr(layout?.pos?.ox, 0) - anchorX * width
    : finiteOr(entry.x, 0);
  const y = useOriginalHeight
    ? parentHeight * finiteOr(layout?.pos?.sy, 0) + finiteOr(layout?.pos?.oy, 0) - anchorY * height
    : finiteOr(entry.y, 0);
  return { parentWidth, parentHeight, width, height, x, y };
}

function median(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return 0;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function vector2(value, fallback) {
  if (!Array.isArray(value) || value.length < 2) return [...fallback];
  return [finiteOr(value[0], fallback[0]), finiteOr(value[1], fallback[1])];
}

function inferredAlignment(start, end, parentSize, leading, center, trailing) {
  const groupCenter = (start + end) / 2;
  const tolerance = Math.max(4, parentSize * 0.04);
  if (Math.abs(groupCenter - parentSize / 2) <= tolerance) return center;
  if (start <= tolerance) return leading;
  if (parentSize - end <= tolerance) return trailing;
  return leading;
}

// Figma cannot represent Roblox UIConstraint/UIGridStyleLayout instances as
// editable visual nodes. They remain in the authored model so runtime
// responsiveness is preserved, but their old values must not override newly
// imported Figma geometry. Expand constraints to admit the new authored size
// and derive layout spacing from visible managed children.
function reconcileSourceOnlyLayout(node, entry, entriesByPath) {
  const geometry = entryGeometry(entry, entriesByPath);
  const constraint = effectChild(node, "UISizeConstraint");
  if (constraint) {
    const props = ensureProperties(constraint);
    const min = vector2(props.MinSize, [0, 0]);
    const max = vector2(props.MaxSize, [100000, 100000]);
    const sizeSx = rebasedSizeScale(
      finiteOr(entry.layout?.size?.sx, 0),
      geometry.width,
      geometry.parentWidth
    );
    const sizeSy = rebasedSizeScale(
      finiteOr(entry.layout?.size?.sy, 0),
      geometry.height,
      geometry.parentHeight
    );
    props.MinSize = [
      Math.round(Math.abs(sizeSx) < 0.001 ? Math.min(min[0], geometry.width) : min[0]),
      Math.round(Math.abs(sizeSy) < 0.001 ? Math.min(min[1], geometry.height) : min[1])
    ];
    props.MaxSize = [
      Math.round(Math.abs(sizeSx) < 0.001 ? Math.max(max[0], geometry.width) : max[0]),
      Math.round(Math.abs(sizeSy) < 0.001 ? Math.max(max[1], geometry.height) : max[1])
    ];
  }

  const layoutNode = childrenOf(node).find((child) =>
    child.ClassName === "UIGridLayout" || child.ClassName === "UIListLayout"
  );
  if (!layoutNode) return;

  const managed = childrenOf(node)
    .filter((child) => child?.Name)
    .map((child) => entriesByPath.get(`${entry.path}/${child.Name}`))
    .filter((childEntry) => childEntry?.layout?.managedByLayout && childEntry.visible !== false)
    .map((childEntry) => ({ entry: childEntry, geometry: entryGeometry(childEntry, entriesByPath) }));
  if (managed.length === 0) {
    // The Figma parent is now a freeform frame. Keeping a source-only Roblox
    // layout helper would rearrange every explicitly positioned child.
    node.Children = childrenOf(node).filter((child) => child !== layoutNode);
    return;
  }
  if (managed.length < 2) return;

  const xRange = Math.max(...managed.map((item) => item.geometry.x))
    - Math.min(...managed.map((item) => item.geometry.x));
  const yRange = Math.max(...managed.map((item) => item.geometry.y))
    - Math.min(...managed.map((item) => item.geometry.y));
  const horizontal = xRange >= yRange;
  const sorted = [...managed].sort((a, b) =>
    horizontal ? a.geometry.x - b.geometry.x : a.geometry.y - b.geometry.y
  );
  const gaps = [];
  for (let index = 1; index < sorted.length; index += 1) {
    const previous = sorted[index - 1].geometry;
    const current = sorted[index].geometry;
    const gap = horizontal
      ? current.x - (previous.x + previous.width)
      : current.y - (previous.y + previous.height);
    if (gap >= 0) gaps.push(gap);
  }
  const padding = Math.max(0, Math.round(median(gaps)));
  const start = Math.min(...managed.map((item) => horizontal ? item.geometry.x : item.geometry.y));
  const end = Math.max(...managed.map((item) =>
    horizontal
      ? item.geometry.x + item.geometry.width
      : item.geometry.y + item.geometry.height
  ));
  const parentSize = horizontal ? geometry.width : geometry.height;
  const widths = managed.map((item) => item.geometry.width);
  const heights = managed.map((item) => item.geometry.height);
  const variableMainSize = horizontal
    ? Math.max(...widths) - Math.min(...widths) > 2
    : Math.max(...heights) - Math.min(...heights) > 2;
  const orthogonalCenters = managed.map((item) =>
    horizontal
      ? item.geometry.y + item.geometry.height / 2
      : item.geometry.x + item.geometry.width / 2
  );
  const singleTrack = Math.max(...orthogonalCenters) - Math.min(...orthogonalCenters)
    <= 2;

  if (layoutNode.ClassName === "UIListLayout" && !singleTrack) {
    node.Children = childrenOf(node).filter((child) => child !== layoutNode);
    for (const item of managed) {
      const childNode = childrenOf(node).find((child) => child?.Name === item.entry.path.split("/").at(-1));
      if (!childNode) continue;
      applyEntry(childNode, {
        ...item.entry,
        layout: {
          ...item.entry.layout,
          managedByLayout: false
        }
      }, entriesByPath);
    }
    return;
  }

  if (layoutNode.ClassName === "UIGridLayout" && variableMainSize && singleTrack) {
    layoutNode.ClassName = "UIListLayout";
    layoutNode.Properties = {};
  }

  if (layoutNode.ClassName === "UIListLayout") {
    const props = ensureProperties(layoutNode);
    props.FillDirection = horizontal ? "Horizontal" : "Vertical";
    props.Padding = { UDim: [0, padding] };
    if (horizontal) {
      props.HorizontalAlignment = inferredAlignment(start, end, parentSize, "Left", "Center", "Right");
      props.VerticalAlignment = "Center";
    } else {
      props.HorizontalAlignment = "Center";
      props.VerticalAlignment = inferredAlignment(start, end, parentSize, "Top", "Center", "Bottom");
    }
    return;
  }

  const props = ensureProperties(layoutNode);
  props.CellSize = {
    UDim2: [[0, Math.round(median(widths))], [0, Math.round(median(heights))]]
  };
  props.CellPadding = {
    UDim2: [[0, horizontal ? padding : 0], [0, horizontal ? 0 : padding]]
  };
  props.FillDirection = horizontal ? "Horizontal" : "Vertical";
  props.FillDirectionMaxCells = managed.length;
  props.HorizontalAlignment = horizontal
    ? inferredAlignment(start, end, geometry.width, "Left", "Center", "Right")
    : "Center";
  props.VerticalAlignment = horizontal
    ? "Center"
    : inferredAlignment(start, end, geometry.height, "Top", "Center", "Bottom");
}

function fontFaceFor(entry) {
  const family = String(entry.fontFamily || "").trim();
  const style = String(entry.fontStyle || "").trim();
  if (!family) return null;
  if (/luckiest guy/i.test(family)) {
    return {
      family: "rbxasset://fonts/families/LuckiestGuy.json",
      weight: "Regular",
      style: "Normal"
    };
  }
  if (/nunito/i.test(family)) {
    const weight = /extra[\s-]*bold/i.test(style)
      ? "ExtraBold"
      : /semi[\s-]*bold/i.test(style)
        ? "SemiBold"
        : /bold/i.test(style)
          ? "Bold"
          : "Regular";
    return {
      family: "rbxasset://fonts/families/Nunito.json",
      weight,
      style: /italic/i.test(style) ? "Italic" : "Normal"
    };
  }
  if (/fredoka/i.test(family)) {
    return {
      family: "rbxasset://fonts/families/FredokaOne.json",
      weight: "Regular",
      style: "Normal"
    };
  }
  return null;
}

function applyEntry(node, entry, entriesByPath) {
  const props = ensureProperties(node);
  const layout = entry.layout;
  if (layout?.size && layout?.pos && layout?.anchor) {
    const geometry = entryGeometry(entry, entriesByPath);
    const parentWidth = geometry.parentWidth;
    const parentHeight = geometry.parentHeight;
    const authoredSizeSx = Number(layout.size.sx) || 0;
    const authoredSizeSy = Number(layout.size.sy) || 0;
    const sizeSx = rebasedSizeScale(authoredSizeSx, geometry.width, parentWidth);
    const sizeSy = rebasedSizeScale(authoredSizeSy, geometry.height, parentHeight);
    const authoredPosSx = Number(layout.pos.sx) || 0;
    const authoredPosSy = Number(layout.pos.sy) || 0;
    const authoredAnchorX = Number(layout.anchor.x) || 0;
    const authoredAnchorY = Number(layout.anchor.y) || 0;
    const width = geometry.width;
    const height = geometry.height;
    const horizontalPosition = rebasedPosition(
      authoredPosSx,
      authoredAnchorX,
      sizeSx,
      geometry.x,
      width,
      parentWidth
    );
    const verticalPosition = rebasedPosition(
      authoredPosSy,
      authoredAnchorY,
      sizeSy,
      geometry.y,
      height,
      parentHeight
    );
    const posSx = horizontalPosition.scale;
    const posSy = verticalPosition.scale;
    const anchorX = horizontalPosition.anchor;
    const anchorY = verticalPosition.anchor;
    props.AnchorPoint = [anchorX, anchorY];
    setUdim2(props, "Size", sizeSx, width - parentWidth * sizeSx, sizeSy, height - parentHeight * sizeSy);
    if (!layout.managedByLayout) {
      setUdim2(props, "Position", posSx, geometry.x + anchorX * width - parentWidth * posSx, posSy, geometry.y + anchorY * height - parentHeight * posSy);
    }
  }

  if (typeof entry.visible === "boolean") props.Visible = entry.visible;
  if (Number.isFinite(entry.rotation)) props.Rotation = Number(entry.rotation);
  if (typeof entry.clipsDescendants === "boolean") {
    props.ClipsDescendants = entry.clipsDescendants;
  }
  if (Number.isFinite(entry.zIndex)) props.ZIndex = Math.round(Number(entry.zIndex));
  if (Number.isFinite(entry.layoutOrder)) props.LayoutOrder = Math.round(Number(entry.layoutOrder));
  if (
    ["None", "X", "Y", "XY"].includes(entry.automaticSize)
  ) {
    props.AutomaticSize = entry.automaticSize;
  }
  if (node.ClassName === "CanvasGroup" && Number.isFinite(entry.opacity)) {
    props.GroupTransparency = 1 - Math.max(0, Math.min(1, Number(entry.opacity)));
  }
  if (
    entry.fill?.color
    && !String(node.ClassName).startsWith("Text")
    && !String(node.ClassName).startsWith("Image")
  ) {
    props.BackgroundColor3 = entry.fill.color.map(Number);
    props.BackgroundTransparency = 1 - Number(entry.fill.opacity ?? 1);
  }
  applyGradient(node, entry);
  if (entry.text !== undefined && String(node.ClassName).startsWith("Text")) props.Text = String(entry.text);
  if (Number.isFinite(entry.fontSize) && String(node.ClassName).startsWith("Text")) props.TextSize = Number(entry.fontSize);
  if (entry.textColor && String(node.ClassName).startsWith("Text")) props.TextColor3 = entry.textColor.map(Number);
  const fontFace = fontFaceFor(entry);
  if (fontFace && String(node.ClassName).startsWith("Text")) props.FontFace = fontFace;
  if (
    ["Left", "Center", "Right"].includes(entry.textAlignHorizontal)
    && String(node.ClassName).startsWith("Text")
  ) {
    props.TextXAlignment = entry.textAlignHorizontal;
  }
  if (
    ["Top", "Center", "Bottom"].includes(entry.textAlignVertical)
    && String(node.ClassName).startsWith("Text")
  ) {
    props.TextYAlignment = entry.textAlignVertical;
  }
  if (typeof entry.textWrapped === "boolean" && String(node.ClassName).startsWith("Text")) {
    props.TextWrapped = entry.textWrapped;
  }

  if (Number.isFinite(entry.cornerRadius)) {
    const corner = ensureEffectChild(node, "UICorner");
    ensureProperties(corner).CornerRadius = { UDim: [0, Math.round(entry.cornerRadius)] };
  }
  applyStroke(node, entry);
}

function verifyModel(modelFile) {
  const model = readJson(modelFile);
  const rootName = path.basename(modelFile).replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
  const { byPath, duplicates } = indexNamedNodes(model, rootName);
  if (!byPath.size) fail(`No named UI objects found in ${modelFile}`);
  if (duplicates.size) fail(`Duplicate bridge paths: ${[...duplicates].join(", ")}`);
  console.log(`Verified ${byPath.size} named UI objects in ${modelFile}`);
}

function enforceRuntimeDefaults(model, rootName) {
  const disableLayerCollectors = (node) => {
    if (["ScreenGui", "BillboardGui", "SurfaceGui"].includes(node?.ClassName)) {
      const props = ensureProperties(node);
      props.Enabled = false;
      props.ResetOnSpawn = false;
    }
    for (const child of childrenOf(node)) disableLayerCollectors(child);
  };
  disableLayerCollectors(model);

  if (rootName !== "TemplateUI") return;
  const root = childrenOf(model).find((child) => child.Name === "Root");
  if (!root) return;
  const screens = childrenOf(root).find((child) => child.Name === "Screens");
  if (screens) {
    for (const screen of childrenOf(screens)) {
      if (screen?.Name) ensureProperties(screen).Visible = false;
    }
  }
}

function bundleWorkspace(workspaceFile, outFile) {
  const workspace = readJson(workspaceFile);
  const requiredFields = ["id", "name", "project", "output"];
  if (
    workspace.format !== "roblox-ui-workspace-v1"
    || !Array.isArray(workspace.models)
    || workspace.models.length === 0
    || requiredFields.some((field) => !String(workspace[field] || "").trim())
  ) {
    fail(`Invalid Figma workspace manifest: ${workspaceFile}`);
  }
  const repositoryRoot = fs.realpathSync(path.resolve(path.dirname(process.argv[1]), ".."));
  const roots = new Set();
  const models = workspace.models.map((definition) => {
    if (!definition?.root || !definition?.path) fail("Every workspace model requires root and path.");
    if (roots.has(definition.root)) fail(`Duplicate workspace root: ${definition.root}`);
    roots.add(definition.root);
    if (path.isAbsolute(definition.path)) fail(`Workspace model path must be repository-relative: ${definition.path}`);
    const unresolvedModelFile = path.resolve(repositoryRoot, definition.path);
    const unresolvedRelative = path.relative(repositoryRoot, unresolvedModelFile);
    if (
      unresolvedRelative === ".."
      || unresolvedRelative.startsWith(`..${path.sep}`)
      || path.isAbsolute(unresolvedRelative)
    ) {
      fail(`Workspace model path leaves the repository: ${definition.path}`);
    }
    if (!fs.existsSync(unresolvedModelFile)) fail(`Workspace model is missing: ${unresolvedModelFile}`);
    const modelFile = fs.realpathSync(unresolvedModelFile);
    const relativeModelFile = path.relative(repositoryRoot, modelFile);
    if (
      relativeModelFile === ".."
      || relativeModelFile.startsWith(`..${path.sep}`)
      || path.isAbsolute(relativeModelFile)
    ) {
      fail(`Workspace model path leaves the repository: ${definition.path}`);
    }
    const expectedRoot = path.basename(modelFile).replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
    if (expectedRoot !== definition.root) {
      fail(`Workspace root ${definition.root} does not match model filename ${expectedRoot}.`);
    }
    verifyModel(modelFile);
    return {
      name: `${definition.root}.model.json`,
      sourcePath: relativeModelFile.split(path.sep).join("/"),
      scope: definition.scope || "production",
      model: readJson(modelFile)
    };
  });
  writeJson(outFile, {
    format: "roblox-ui-workspace-v1",
    id: workspace.id,
    name: workspace.name,
    preset: workspace.preset,
    project: workspace.project,
    output: workspace.output,
    generatedAt: new Date().toISOString(),
    models
  });
  console.log(`Bundled ${models.length} authored UI models into ${outFile}`);
}

if (command === "bundle") {
  const workspaceFile = option("--workspace");
  const outFile = option("--out");
  if (!workspaceFile || !outFile) {
    fail("Usage: node scripts/figma-ui-bridge.mjs bundle --workspace <workspace.json> --out <workspace-bundle.json>");
  }
  bundleWorkspace(workspaceFile, outFile);
} else if (command === "verify") {
  const modelFile = option("--model");
  if (!modelFile) fail("Usage: node scripts/figma-ui-bridge.mjs verify --model <TemplateUI.model.json>");
  verifyModel(modelFile);
} else if (command === "self-test") {
  const modelFile = option("--model");
  if (!modelFile) fail("Usage: node scripts/figma-ui-bridge.mjs self-test --model <TemplateUI.model.json>");
  const model = readJson(modelFile);
  const rootName = path.basename(modelFile).replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
  const { byPath } = indexNamedNodes(model, rootName);
  const targetPath = `${rootName}/Root/CurrencyTray`;
  const target = byPath.get(targetPath);
  if (!target) fail(`Self-test target missing: ${targetPath}`);
  applyEntry(target, {
    path: targetPath,
    className: target.ClassName,
    visible: false,
    fill: { color: [0.1, 0.2, 0.3], opacity: 0.75 }
  });
  if (target.Properties.Visible !== false) fail("Figma bridge self-test did not apply visibility.");
  if (target.Properties.BackgroundTransparency !== 0.25) fail("Figma bridge self-test did not apply opacity.");
  console.log(`Figma bridge self-test passed for ${modelFile}`);
} else if (command === "apply") {
  const modelFile = option("--model");
  const patchFile = option("--patch");
  const outFile = option("--out") || modelFile;
  if (!modelFile || !patchFile) {
    fail(
      "Usage: node scripts/figma-ui-bridge.mjs apply --model <model> --patch <patch> "
      + "[--out <model>] [--exclude-path <root/path>]"
    );
  }

  const preservePrettyFormatting = fs.readFileSync(modelFile, "utf8").trim().includes("\n");
  const model = readJson(modelFile);
  const patch = readJson(patchFile);
  if (patch.format !== "roblox-ui-bridge-v1" || !Array.isArray(patch.entries)) fail("Unsupported or invalid Figma patch.");
  const patchRoots = new Set(Array.isArray(patch.roots) ? patch.roots.map(String) : []);
  const excludedPaths = options("--exclude-path")
    .map((entryPath) => entryPath.replace(/\/+$/, ""))
    .filter(Boolean);
  const isExcluded = (entryPath) => excludedPaths.some(
    (excludedPath) => entryPath === excludedPath || entryPath.startsWith(`${excludedPath}/`)
  );
  const effectiveEntries = patch.entries.filter(
    (entry) => typeof entry?.path !== "string" || !isExcluded(entry.path)
  );
  const rootName = path.basename(modelFile).replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
  if (!patchRoots.has(rootName)) fail(`Patch does not declare authoritative root ${rootName}.`);
  const { byPath, duplicates } = indexNamedNodes(model, rootName);
  if (duplicates.size) fail(`Model contains duplicate bridge paths: ${[...duplicates].join(", ")}`);
  const entriesByPath = new Map();
  for (const entry of effectiveEntries) {
    if (!entry?.path || entriesByPath.has(entry.path)) {
      fail(`Patch contains a missing or duplicate entry path: ${entry?.path || "<missing>"}`);
    }
    entriesByPath.set(entry.path, entry);
  }

  let applied = 0;
  let created = 0;
  let retyped = 0;
  const rootEntries = effectiveEntries
    .filter((entry) => entry?.path?.startsWith(`${rootName}/`))
    .sort((left, right) => left.path.split("/").length - right.path.split("/").length);
  for (const entry of rootEntries) {
    const segments = entry.path.split("/");
    if (
      segments.some((segment) => !segment || segment === "." || segment === "..")
      || segments[0] !== rootName
    ) {
      fail(`Patch contains an invalid authoritative path: ${entry.path}`);
    }
    let node = byPath.get(entry.path);
    if (!node) {
      if (!FIGMA_VISUAL_CLASSES.has(entry.className)) {
        fail(`Cannot create unsupported Figma class ${entry.className || "<missing>"} at ${entry.path}.`);
      }
      const parentPath = segments.slice(0, -1).join("/");
      const parent = parentPath === rootName ? model : byPath.get(parentPath);
      if (!parent) {
        fail(`Cannot create ${entry.path}; authoritative parent ${parentPath} is missing.`);
      }
      node = {
        Name: segments.at(-1),
        ClassName: entry.className,
        Properties: {},
        Children: []
      };
      parent.Children ||= [];
      parent.Children.push(node);
      byPath.set(entry.path, node);
      created += 1;
    }
    if (entry.className && entry.className !== node.ClassName) {
      if (
        !FIGMA_VISUAL_CLASSES.has(entry.className)
        || !FIGMA_VISUAL_CLASSES.has(node.ClassName)
      ) {
        fail(`Class mismatch at ${entry.path}: patch ${entry.className}, model ${node.ClassName}`);
      }
      node.ClassName = entry.className;
      node.Properties = {};
      retyped += 1;
    }
    applyEntry(node, entry, entriesByPath);
    applied += 1;
  }
  for (const entry of rootEntries) {
    const node = byPath.get(entry.path);
    if (node) reconcileSourceOnlyLayout(node, entry, entriesByPath);
  }
  const removedPaths = pruneToAuthoritativeEntries(model, rootName, entriesByPath);
  const authoritativeIndex = indexNamedNodes(model, rootName);
  const missingAfterPrune = [...entriesByPath.keys()]
    .filter((entryPath) => entryPath.startsWith(`${rootName}/`))
    .filter((entryPath) => !authoritativeIndex.byPath.has(entryPath));
  if (missingAfterPrune.length) {
    fail(`Authoritative import removed required Figma paths:\n${missingAfterPrune.join("\n")}`);
  }
  enforceRuntimeDefaults(model, rootName);
  writeJson(outFile, model, preservePrettyFormatting);
  console.log(
    `Applied ${applied} authoritative Figma visual upserts `
    + `(${created} created, ${retyped} retyped) to ${outFile}; `
    + `removed ${removedPaths.length} legacy visual branches`
    + (excludedPaths.length ? ` and excluded ${excludedPaths.length} obsolete Figma paths.` : ".")
  );
} else {
  fail("Commands: bundle, verify, apply");
}
