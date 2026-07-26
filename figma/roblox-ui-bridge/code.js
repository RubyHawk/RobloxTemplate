if (typeof figma !== "undefined") {
  figma.showUI(__html__, { width: 420, height: 650, themeColors: true });
}

const NAMESPACE = "roblox_ui_bridge";
const DEFAULT_VIEWPORT = { width: 1600, height: 900 };
const DEFAULT_SURFACE_CANVAS = { width: 800, height: 600 };
const DEFAULT_BILLBOARD_PIXELS_PER_STUD = 100;
const DISPLAY_CLASSES = new Set(["ScreenGui", "SurfaceGui", "BillboardGui"]);
const VISUAL_CLASSES = new Set([
  "Frame", "ScrollingFrame", "CanvasGroup", "TextLabel", "TextButton", "TextBox",
  "ImageLabel", "ImageButton", "ViewportFrame", "VideoFrame"
]);

function property(object, name, fallback) {
  return object && object.Properties && object.Properties[name] !== undefined ? object.Properties[name] : fallback;
}

function color(value, fallback) {
  if (!Array.isArray(value) || value.length < 3) return fallback;
  return { r: Number(value[0]), g: Number(value[1]), b: Number(value[2]) };
}

function vector2(value, fallback = { width: 0, height: 0 }) {
  const raw = value && Array.isArray(value.Vector2) ? value.Vector2 : value;
  if (!Array.isArray(raw) || raw.length < 2) return { ...fallback };
  const width = Number(raw[0]);
  const height = Number(raw[1]);
  if (!Number.isFinite(width) || !Number.isFinite(height)) return { ...fallback };
  return { width, height };
}

function vector3(value) {
  const raw = value && Array.isArray(value.Vector3) ? value.Vector3 : value;
  if (!Array.isArray(raw) || raw.length < 3) return null;
  const result = raw.slice(0, 3).map(Number);
  return result.every(Number.isFinite) ? result : null;
}

function udim2(value) {
  const raw = value && value.UDim2;
  if (!raw || !raw[0] || !raw[1]) return { sx: 0, ox: 0, sy: 0, oy: 0 };
  return { sx: Number(raw[0][0]), ox: Number(raw[0][1]), sy: Number(raw[1][0]), oy: Number(raw[1][1]) };
}

function anchor(value) {
  return Array.isArray(value) ? { x: Number(value[0]), y: Number(value[1]) } : { x: 0, y: 0 };
}

function constraint(positionScale, sizeScale, anchorValue) {
  if (Math.abs(sizeScale - 1) < 0.001) return "STRETCH";
  if (Math.abs(positionScale - 0.5) < 0.001 && Math.abs(anchorValue - 0.5) < 0.001) return "CENTER";
  if (positionScale >= 0.999 && anchorValue >= 0.999) return "MAX";
  return "MIN";
}

function namedChildren(object) {
  return Array.isArray(object && object.Children) ? object.Children.filter((child) => child && child.Name) : [];
}

function childOfClass(object, className) {
  return (object.Children || []).find((child) => child.ClassName === className);
}

function alignment(value) {
  const normalized = String(value || "Left").toLowerCase();
  if (normalized === "center") return "CENTER";
  if (normalized === "right" || normalized === "bottom") return "MAX";
  return "MIN";
}

function layoutPadding(layout) {
  const raw = property(layout, "Padding", { UDim: [0, 0] }).UDim || [0, 0];
  return Math.max(0, Number(raw[1]) || 0);
}

function gridPadding(layout) {
  const raw = property(layout, "CellPadding", { UDim2: [[0, 0], [0, 0]] }).UDim2 || [[0, 0], [0, 0]];
  return { x: Math.max(0, Number(raw[0]?.[1]) || 0), y: Math.max(0, Number(raw[1]?.[1]) || 0) };
}

function applyLayout(node, object) {
  const list = childOfClass(object, "UIListLayout");
  const grid = childOfClass(object, "UIGridLayout");
  if (!list && !grid) return false;

  const layout = list || grid;
  const direction = grid ? "Horizontal" : property(layout, "FillDirection", "Vertical");
  node.layoutMode = String(direction).toLowerCase() === "horizontal" ? "HORIZONTAL" : "VERTICAL";
  node.primaryAxisSizingMode = "FIXED";
  node.counterAxisSizingMode = "FIXED";
  const spacing = grid ? gridPadding(layout) : { x: layoutPadding(layout), y: layoutPadding(layout) };
  node.itemSpacing = node.layoutMode === "HORIZONTAL" ? spacing.x : spacing.y;
  node.primaryAxisAlignItems = node.layoutMode === "HORIZONTAL"
    ? alignment(property(layout, "HorizontalAlignment", "Left"))
    : alignment(property(layout, "VerticalAlignment", "Top"));
  node.counterAxisAlignItems = node.layoutMode === "HORIZONTAL"
    ? alignment(property(layout, "VerticalAlignment", "Top"))
    : alignment(property(layout, "HorizontalAlignment", "Left"));
  if (grid) {
    node.layoutWrap = "WRAP";
    node.counterAxisSpacing = node.layoutMode === "HORIZONTAL" ? spacing.y : spacing.x;
  }
  return true;
}

function partSize(object) {
  return vector3(property(object, "Size", null));
}

function surfacePixelsFromPart(surface, ancestorPart) {
  const size = partSize(ancestorPart);
  const pixelsPerStud = Number(property(surface, "PixelsPerStud", 0));
  if (!size || !Number.isFinite(pixelsPerStud) || pixelsPerStud <= 0) return null;
  const face = String(property(surface, "Face", "Front"));
  if (face === "Top" || face === "Bottom") {
    return { width: size[0] * pixelsPerStud, height: size[2] * pixelsPerStud };
  }
  if (face === "Left" || face === "Right") {
    return { width: size[2] * pixelsPerStud, height: size[1] * pixelsPerStud };
  }
  return { width: size[0] * pixelsPerStud, height: size[1] * pixelsPerStud };
}

function positiveCanvas(size, fallback) {
  const width = Number(size && size.width);
  const height = Number(size && size.height);
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return { ...fallback };
  return { width: Math.max(1, Math.round(width)), height: Math.max(1, Math.round(height)) };
}

function displayCanvasSize(container, ancestorPart = null) {
  if (!container || container.ClassName === "ScreenGui") return { ...DEFAULT_VIEWPORT };
  if (container.ClassName === "SurfaceGui") {
    const sizingMode = String(property(container, "SizingMode", "FixedSize"));
    if (sizingMode === "PixelsPerStud") {
      return positiveCanvas(surfacePixelsFromPart(container, ancestorPart), DEFAULT_SURFACE_CANVAS);
    }
    const authoredCanvas = vector2(property(container, "CanvasSize", null));
    if (authoredCanvas.width > 0 && authoredCanvas.height > 0) {
      return positiveCanvas(authoredCanvas, DEFAULT_SURFACE_CANVAS);
    }
    const partCanvas = surfacePixelsFromPart(container, ancestorPart);
    return positiveCanvas(partCanvas, DEFAULT_SURFACE_CANVAS);
  }
  if (container.ClassName === "BillboardGui") {
    const size = udim2(property(container, "Size", null));
    return positiveCanvas({
      width: Math.abs(size.ox) > 0 ? Math.abs(size.ox) : Math.abs(size.sx) * DEFAULT_BILLBOARD_PIXELS_PER_STUD,
      height: Math.abs(size.oy) > 0 ? Math.abs(size.oy) : Math.abs(size.sy) * DEFAULT_BILLBOARD_PIXELS_PER_STUD
    }, { width: 400, height: 160 });
  }
  return { ...DEFAULT_VIEWPORT };
}

function collectDisplayContainers(model, rootName) {
  const result = [];
  const visit = (node, currentPath, ancestorPart) => {
    const nextPart = partSize(node) ? node : ancestorPart;
    if (DISPLAY_CLASSES.has(node.ClassName)) {
      result.push({
        node,
        path: currentPath,
        size: displayCanvasSize(node, nextPart),
        ancestorPart: nextPart
      });
      return;
    }
    for (const child of namedChildren(node)) {
      visit(child, `${currentPath}/${child.Name}`, nextPart);
    }
  };

  if (DISPLAY_CLASSES.has(model.ClassName)) {
    visit(model, rootName, null);
  } else {
    const modelPart = partSize(model) ? model : null;
    for (const child of namedChildren(model)) {
      visit(child, `${rootName}/${child.Name}`, modelPart);
    }
  }
  return result;
}

function collectVisualPaths(object, path) {
  const result = [];
  const visit = (node, currentPath) => {
    if (VISUAL_CLASSES.has(node.ClassName)) result.push(currentPath);
    for (const child of namedChildren(node)) visit(child, `${currentPath}/${child.Name}`);
  };
  for (const child of namedChildren(object)) visit(child, `${path}/${child.Name}`);
  return result;
}

let availableFontsPromise;
const loadedFonts = new Map();

async function chooseFont(object) {
  const raw = property(object, "FontFace", null);
  const familyUrl = raw && raw.family ? raw.family : "";
  const wantedFamily = familyUrl.includes("Fredoka") ? "Fredoka" : familyUrl.includes("Nunito") ? "Nunito" : "Inter";
  const wantedStyle = raw && /bold/i.test(String(raw.weight)) ? "Bold" : "Regular";
  availableFontsPromise ||= figma.listAvailableFontsAsync();
  const fonts = await availableFontsPromise;
  const match = fonts.find((entry) => entry.fontName.family === wantedFamily && entry.fontName.style === wantedStyle)
    || fonts.find((entry) => entry.fontName.family === wantedFamily)
    || fonts.find((entry) => entry.fontName.family === "Inter" && entry.fontName.style === "Regular")
    || fonts[0];
  const fontKey = `${match.fontName.family}/${match.fontName.style}`;
  if (!loadedFonts.has(fontKey)) loadedFonts.set(fontKey, figma.loadFontAsync(match.fontName));
  await loadedFonts.get(fontKey);
  return match.fontName;
}

function storeMetadata(node, data) {
  node.setSharedPluginData(NAMESPACE, "path", data.path);
  node.setSharedPluginData(NAMESPACE, "className", data.className);
  node.setSharedPluginData(NAMESPACE, "layout", JSON.stringify(data.layout));
  if (data.image) node.setSharedPluginData(NAMESPACE, "image", data.image);
}

async function createVisualTree(object, parent, path, parentSize, forceVisible, managedByLayout = false) {
  if (VISUAL_CLASSES.has(object.ClassName)) {
    return createVisual(object, parent, path, parentSize, forceVisible, managedByLayout);
  }
  for (const child of namedChildren(object)) {
    await createVisualTree(child, parent, `${path}/${child.Name}`, parentSize, forceVisible, managedByLayout);
  }
  return null;
}

async function createVisual(object, parent, path, parentSize, forceVisible, managedByLayout = false) {
  if (!VISUAL_CLASSES.has(object.ClassName)) return null;

  const isText = object.ClassName.startsWith("Text");
  const isImage = object.ClassName.startsWith("Image");
  const node = figma.createFrame();
  node.name = object.Name || object.ClassName;
  parent.appendChild(node);
  node.clipsContent = property(object, "ClipsDescendants", false) === true;

  const size = udim2(property(object, "Size", { UDim2: [[0, 100], [0, 50]] }));
  const pos = udim2(property(object, "Position", { UDim2: [[0, 0], [0, 0]] }));
  const anch = anchor(property(object, "AnchorPoint", [0, 0]));
  const width = Math.max(1, parentSize.width * size.sx + size.ox);
  const height = Math.max(1, parentSize.height * size.sy + size.oy);
  const x = parentSize.width * pos.sx + pos.ox - anch.x * width;
  const y = parentSize.height * pos.sy + pos.oy - anch.y * height;

  node.resize(width, height);
  node.x = x;
  node.y = y;
  node.constraints = {
    horizontal: constraint(pos.sx, size.sx, anch.x),
    vertical: constraint(pos.sy, size.sy, anch.y)
  };
  node.visible = forceVisible || property(object, "Visible", true) !== false;
  const groupTransparency = Number(property(object, "GroupTransparency", 0));
  node.opacity = Math.max(0, Math.min(1, 1 - (Number.isFinite(groupTransparency) ? groupTransparency : 0)));

  const backgroundTransparency = Number(property(object, "BackgroundTransparency", isImage ? 1 : 0));
  const background = color(property(object, "BackgroundColor3", null), { r: 0.94, g: 0.92, b: 1 });
  node.fills = backgroundTransparency >= 1 ? [] : [{ type: "SOLID", color: background, opacity: 1 - backgroundTransparency }];

  const corner = childOfClass(object, "UICorner");
  if (corner) {
    const radius = property(corner, "CornerRadius", { UDim: [0, 0] }).UDim || [0, 0];
    node.cornerRadius = Math.max(0, Number(radius[1]) + Math.min(width, height) * Number(radius[0]));
  }
  const stroke = childOfClass(object, "UIStroke");
  if (stroke) {
    node.strokes = [{ type: "SOLID", color: color(property(stroke, "Color", null), { r: 0.05, g: 0.04, b: 0.12 }), opacity: 1 - Number(property(stroke, "Transparency", 0)) }];
    node.strokeWeight = Math.max(0, Number(property(stroke, "Thickness", 1)));
  }

  if (isText) {
    const textNode = figma.createText();
    textNode.name = "$Text";
    node.appendChild(textNode);
    textNode.fontName = await chooseFont(object);
    textNode.fontSize = Math.max(1, Number(property(object, "TextSize", 16)));
    textNode.textAutoResize = "NONE";
    textNode.resize(width, height);
    textNode.x = 0;
    textNode.y = 0;
    textNode.characters = String(property(object, "Text", object.Name || "Text"));
    textNode.fills = [{ type: "SOLID", color: color(property(object, "TextColor3", null), { r: 0.06, g: 0.05, b: 0.12 }), opacity: 1 - Number(property(object, "TextTransparency", 0)) }];
    textNode.textAlignHorizontal = String(property(object, "TextXAlignment", "Center")).toUpperCase();
    textNode.textAlignVertical = String(property(object, "TextYAlignment", "Center")).toUpperCase();
  }

  if (isImage) {
    node.fills = [{
      type: "SOLID",
      color: { r: 0.88, g: 0.84, b: 1 },
      opacity: Math.max(0.18, 1 - Number(property(object, "ImageTransparency", 0)))
    }];
    node.dashPattern = [6, 4];
    node.strokes = [{ type: "SOLID", color: { r: 0.49, g: 0.23, b: 0.93 } }];
  }

  storeMetadata(node, {
    path,
    className: object.ClassName,
    image: isImage ? String(property(object, "Image", "")) : "",
    layout: { size, pos, anchor: anch, parentWidth: parentSize.width, parentHeight: parentSize.height, managedByLayout }
  });

  // Roblox text controls can contain authored visual children. TextButton is
  // commonly the root of an icon button (IconBubble, Icon, label, badge, ...),
  // so treating it as a leaf silently discards most of the editable control.
  const childManagedByLayout = Boolean(childOfClass(object, "UIListLayout") || childOfClass(object, "UIGridLayout"));
  for (const child of namedChildren(object)) {
    await createVisualTree(child, node, `${path}/${child.Name}`, { width, height }, false, childManagedByLayout);
  }
  applyLayout(node, object);
  return node;
}

function findNamed(object, name) {
  return (object.Children || []).find((child) => child.Name === name);
}

function createPlacementCursor(page) {
  let nextY = 0;
  for (const child of page.children) {
    if (typeof child.y === "number" && typeof child.height === "number") {
      nextY = Math.max(nextY, child.y + child.height + 160);
    }
  }
  return { x: 0, y: nextY, rowHeight: 0, maxRowWidth: 4600 };
}

function placeBoard(board, cursor) {
  if (cursor.x > 0 && cursor.x + board.width > cursor.maxRowWidth) {
    cursor.x = 0;
    cursor.y += cursor.rowHeight + 120;
    cursor.rowHeight = 0;
  }
  board.x = cursor.x;
  board.y = cursor.y;
  cursor.x += board.width + 120;
  cursor.rowHeight = Math.max(cursor.rowHeight, board.height);
}

function createBoard(rootName, label, size, containerPath, containerClass, cursor, contentPath = containerPath) {
  const board = figma.createFrame();
  board.name = `${rootName} - ${label}`;
  board.resize(size.width, size.height);
  board.clipsContent = true;
  board.fills = [{
    type: "SOLID",
    color: containerClass === "ScreenGui" ? { r: 0.16, g: 0.67, b: 0.93 } : { r: 0.08, g: 0.07, b: 0.16 }
  }];
  board.setSharedPluginData(NAMESPACE, "modelRoot", rootName);
  board.setSharedPluginData(NAMESPACE, "containerPath", containerPath);
  board.setSharedPluginData(NAMESPACE, "containerClass", containerClass);
  board.setSharedPluginData(NAMESPACE, "contentPath", contentPath);
  placeBoard(board, cursor);
  return board;
}

async function importModel(file, cursor) {
  const model = file.model && typeof file.model === "object" ? file.model : JSON.parse(file.text);
  const rootName = String(file.name || "RobloxUI").replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
  const modelRoot = findNamed(model, "Root") || model;
  const screens = findNamed(modelRoot, "Screens");
  const artboards = [];

  if (screens) {
    const hud = createBoard(
      rootName,
      "HUD",
      DEFAULT_VIEWPORT,
      rootName,
      "ScreenGui",
      cursor,
      `${rootName}/Root`
    );
    const excluded = new Set(["Screens"]);
    for (const child of namedChildren(modelRoot)) {
      if (!excluded.has(child.Name)) {
        await createVisualTree(child, hud, `${rootName}/Root/${child.Name}`, DEFAULT_VIEWPORT, false);
      }
    }
    artboards.push(hud);

    for (const screen of namedChildren(screens)) {
      if (!VISUAL_CLASSES.has(screen.ClassName)) continue;
      const board = createBoard(rootName, screen.Name, DEFAULT_VIEWPORT, `${rootName}/Root/Screens/${screen.Name}`, "ScreenGui", cursor);
      await createVisual(screen, board, `${rootName}/Root/Screens/${screen.Name}`, DEFAULT_VIEWPORT, true);
      artboards.push(board);
    }
    return artboards;
  }

  const containers = collectDisplayContainers(model, rootName);
  if (containers.length) {
    for (const container of containers) {
      const label = container.path === rootName
        ? container.node.ClassName
        : `${container.node.Name} (${container.node.ClassName})`;
      const board = createBoard(rootName, label, container.size, container.path, container.node.ClassName, cursor);
      for (const child of namedChildren(container.node)) {
        await createVisualTree(child, board, `${container.path}/${child.Name}`, container.size, false);
      }
      artboards.push(board);
    }
    return artboards;
  }

  const board = createBoard(rootName, "UI", DEFAULT_VIEWPORT, rootName, model.ClassName || "Model", cursor);
  const prefix = modelRoot.Name === "Root" ? `${rootName}/Root` : rootName;
  for (const child of namedChildren(modelRoot)) {
    await createVisualTree(child, board, `${prefix}/${child.Name}`, DEFAULT_VIEWPORT, false);
  }
  artboards.push(board);
  return artboards;
}

function expandImportFiles(files) {
  const expanded = [];
  for (const file of files || []) {
    const parsed = JSON.parse(file.text);
    if (parsed && parsed.format === "roblox-ui-workspace-v1" && Array.isArray(parsed.models)) {
      for (const item of parsed.models) {
        if (item && item.name && item.model) {
          expanded.push({ name: item.name, model: item.model, workspaceId: String(parsed.id || "") });
        }
      }
    } else {
      expanded.push({ name: file.name, model: parsed });
    }
  }
  return expanded;
}

function solidPaint(node) {
  if (!("fills" in node) || !Array.isArray(node.fills)) return null;
  const paint = node.fills.find((fill) => fill.type === "SOLID");
  return paint ? { color: [paint.color.r, paint.color.g, paint.color.b], opacity: paint.opacity === undefined ? 1 : paint.opacity } : null;
}

function directTextNode(node) {
  if (!("children" in node)) return null;
  return node.children.find((child) => child.type === "TEXT" && child.name === "$Text")
    || node.children.find((child) => child.type === "TEXT")
    || null;
}

function imagePaint(node) {
  if (!("fills" in node) || !Array.isArray(node.fills)) return null;
  return node.fills.find((fill) => fill.type === "IMAGE") || null;
}

function inferredBinding(node) {
  const tagged = String(node.name || "").match(
    /^(.*?)\s*\[(CanvasGroup|Frame|ImageButton|ImageLabel|ScrollingFrame|TextBox|TextButton|TextLabel|VideoFrame|ViewportFrame)\]\s*$/
  );
  const name = String(tagged ? tagged[1] : node.name || "").trim();
  if (!name || name === "$Text" || name.includes("/")) return null;
  if (tagged) return { name, className: tagged[2] };

  const interactive = /(Button|Tab|Toggle)$/i.test(name);
  if (directTextNode(node)) {
    return { name, className: interactive ? "TextButton" : "TextLabel" };
  }
  if (imagePaint(node)) {
    return { name, className: interactive ? "ImageButton" : "ImageLabel" };
  }
  return { name, className: "Frame" };
}

function axisLayout(constraintValue, start, size, parentSize) {
  if (constraintValue === "STRETCH") {
    return { sizeScale: 1, sizeOffset: size - parentSize, posScale: 0, posOffset: start, anchor: 0 };
  }
  if (constraintValue === "CENTER") {
    return {
      sizeScale: 0,
      sizeOffset: size,
      posScale: 0.5,
      posOffset: start + size / 2 - parentSize / 2,
      anchor: 0.5
    };
  }
  if (constraintValue === "MAX") {
    return {
      sizeScale: 0,
      sizeOffset: size,
      posScale: 1,
      posOffset: start + size - parentSize,
      anchor: 1
    };
  }
  return { sizeScale: 0, sizeOffset: size, posScale: 0, posOffset: start, anchor: 0 };
}

function inferredLayout(node) {
  const parentWidth = Number(node.parent && "width" in node.parent ? node.parent.width : 0);
  const parentHeight = Number(node.parent && "height" in node.parent ? node.parent.height : 0);
  const constraints = node.constraints || { horizontal: "MIN", vertical: "MIN" };
  const horizontal = axisLayout(
    constraints.horizontal,
    Number(node.x) || 0,
    Number(node.width) || 1,
    parentWidth
  );
  const vertical = axisLayout(
    constraints.vertical,
    Number(node.y) || 0,
    Number(node.height) || 1,
    parentHeight
  );
  return {
    size: {
      sx: horizontal.sizeScale,
      ox: horizontal.sizeOffset,
      sy: vertical.sizeScale,
      oy: vertical.sizeOffset
    },
    pos: {
      sx: horizontal.posScale,
      ox: horizontal.posOffset,
      sy: vertical.posScale,
      oy: vertical.posOffset
    },
    anchor: { x: horizontal.anchor, y: vertical.anchor },
    parentWidth,
    parentHeight,
    managedByLayout: Boolean(
      node.parent
      && "layoutMode" in node.parent
      && node.parent.layoutMode
      && node.parent.layoutMode !== "NONE"
    )
  };
}

function boardContentPath(board) {
  const explicit = board.getSharedPluginData(NAMESPACE, "contentPath");
  if (explicit) return explicit;
  const containerPath = board.getSharedPluginData(NAMESPACE, "containerPath");
  const modelRoot = board.getSharedPluginData(NAMESPACE, "modelRoot");
  if (containerPath === modelRoot && modelRoot) return `${modelRoot}/Root`;
  return containerPath || modelRoot || "";
}

function collectPatch(nodes) {
  const entries = [];
  const visit = (node, parentPath = "") => {
    const isBoard = Boolean(
      node.getSharedPluginData
      && node.getSharedPluginData(NAMESPACE, "modelRoot")
      && node.getSharedPluginData(NAMESPACE, "containerPath")
    );
    if (isBoard) {
      const contentPath = boardContentPath(node);
      if ("children" in node) node.children.forEach((child) => visit(child, contentPath));
      return;
    }

    let path = node.getSharedPluginData ? node.getSharedPluginData(NAMESPACE, "path") : "";
    let className = node.getSharedPluginData
      ? node.getSharedPluginData(NAMESPACE, "className")
      : "";
    if (!path && parentPath && node.type !== "TEXT") {
      const binding = inferredBinding(node);
      if (binding) {
        path = `${parentPath}/${binding.name}`;
        className = binding.className;
        storeMetadata(node, {
          path,
          className,
          layout: inferredLayout(node)
        });
      }
    }
    if (path) {
      const rawLayout = node.getSharedPluginData(NAMESPACE, "layout");
      const layout = rawLayout ? JSON.parse(rawLayout) : inferredLayout(node);
      if (layout && node.parent && "width" in node.parent && "height" in node.parent) {
        layout.parentWidth = node.parent.width;
        layout.parentHeight = node.parent.height;
      }
      const entry = {
        path,
        className,
        visible: node.visible,
        opacity: node.opacity,
        x: node.x,
        y: node.y,
        width: node.width,
        height: node.height,
        // Image frames use a synthetic fill to make otherwise unavailable
        // Roblox assets visible in Figma. It is not a Roblox background edit.
        fill: String(className).startsWith("Image") ? null : solidPaint(node),
        layout
      };
      if (String(entry.className).startsWith("Text") && "children" in node) {
        const textNode = directTextNode(node);
        entry.text = textNode ? textNode.characters : "";
        entry.fontSize = textNode && typeof textNode.fontSize === "number" ? textNode.fontSize : null;
        if (textNode && typeof textNode.fontName !== "symbol") {
          entry.fontFamily = textNode.fontName.family;
          entry.fontStyle = textNode.fontName.style;
          entry.textAlignHorizontal = String(textNode.textAlignHorizontal || "CENTER")
            .toLowerCase()
            .replace(/^./, (value) => value.toUpperCase());
        }
        const textPaint = textNode ? solidPaint(textNode) : null;
        entry.textColor = textPaint ? textPaint.color : null;
      }
      entry.cornerRadius = typeof node.cornerRadius === "number" ? node.cornerRadius : null;
      if (Array.isArray(node.strokes)) {
        const stroke = node.strokes.find((paint) => paint.type === "SOLID");
        if (stroke) entry.stroke = { color: [stroke.color.r, stroke.color.g, stroke.color.b], thickness: node.strokeWeight };
      }
      entries.push(entry);
    }
    if ("children" in node) node.children.forEach((child) => visit(child, path || parentPath));
  };
  nodes.forEach((node) => visit(node, ""));
  return entries;
}

function workspaceIdsForNodes(nodes) {
  const ids = new Set();
  for (const node of nodes) {
    let current = node;
    while (current) {
      if (current.getSharedPluginData) {
        const workspaceId = current.getSharedPluginData(NAMESPACE, "workspaceId");
        if (workspaceId) ids.add(workspaceId);
      }
      current = current.parent;
    }
  }
  return [...ids];
}

function singleWorkspaceId(nodes) {
  const workspaceIds = workspaceIdsForNodes(nodes);
  if (workspaceIds.length > 1) {
    throw new Error(`Selection spans multiple workspaces (${workspaceIds.join(", ")}). Export one workspace at a time.`);
  }
  return workspaceIds[0] || "";
}

if (typeof figma !== "undefined") {
  figma.ui.onmessage = async (message) => {
    try {
      if (message.type === "close") return figma.closePlugin();
      if (message.type === "import-models") {
        const files = expandImportFiles(message.files);
        const cursor = createPlacementCursor(figma.currentPage);
        const artboards = [];
        for (const file of files) {
          const imported = await importModel(file, cursor);
          for (const artboard of imported) {
            if (file.workspaceId) artboard.setSharedPluginData(NAMESPACE, "workspaceId", file.workspaceId);
          }
          artboards.push(...imported);
        }
        figma.currentPage.selection = artboards;
        if (artboards.length) figma.viewport.scrollAndZoomIntoView(artboards);
        figma.ui.postMessage({
          type: "status",
          text: `Imported ${artboards.length} editable artboards on this page. ScreenGui, SurfaceGui, and BillboardGui containers are supported.`
        });
        return;
      }
      if (message.type === "export-patch") {
        const selectedEntries = collectPatch(figma.currentPage.selection);
        const selectedNodes = selectedEntries.length ? figma.currentPage.selection : figma.currentPage.children;
        const selectedWorkspaceId = singleWorkspaceId(selectedNodes);
        const sourceNodes = selectedWorkspaceId
          ? figma.currentPage.children.filter(
            (node) => node.getSharedPluginData
              && node.getSharedPluginData(NAMESPACE, "workspaceId") === selectedWorkspaceId
          )
          : selectedNodes;
        const entries = collectPatch(sourceNodes);
        if (!entries.length) throw new Error("Import a Roblox UI model on this page first.");
        const duplicatePaths = entries
          .map((entry) => entry.path)
          .filter((entryPath, index, paths) => paths.indexOf(entryPath) !== index);
        if (duplicatePaths.length) {
          throw new Error(
            `Duplicate Roblox paths found in Figma: ${[...new Set(duplicatePaths)].join(", ")}. `
            + "Rename or remove the duplicate layers before export."
          );
        }
        const declaredRoots = sourceNodes
          .map((node) => node.getSharedPluginData
            ? node.getSharedPluginData(NAMESPACE, "modelRoot")
            : "")
          .filter(Boolean);
        const roots = [...new Set([
          ...declaredRoots,
          ...entries.map((entry) => entry.path.split("/")[0])
        ])];
        const workspaceId = singleWorkspaceId(sourceNodes);
        const patch = {
          format: "roblox-ui-bridge-v1",
          mode: "authoritative",
          exportedAt: new Date().toISOString(),
          workspace: workspaceId || undefined,
          roots,
          entries
        };
        figma.ui.postMessage({
          type: "download",
          name: `${roots.join("-") || "roblox-ui"}.figma-patch.json`,
          text: JSON.stringify(patch, null, 2)
        });
      }
    } catch (error) {
      figma.ui.postMessage({ type: "status", text: `Error: ${error && error.message ? error.message : String(error)}` });
    }
  };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    DEFAULT_VIEWPORT,
    DEFAULT_SURFACE_CANVAS,
    DISPLAY_CLASSES,
    VISUAL_CLASSES,
    collectDisplayContainers,
    collectVisualPaths,
    displayCanvasSize,
    expandImportFiles,
    inferredBinding,
    inferredLayout,
    singleWorkspaceId,
    surfacePixelsFromPart,
    udim2,
    vector2,
    workspaceIdsForNodes
  };
}
