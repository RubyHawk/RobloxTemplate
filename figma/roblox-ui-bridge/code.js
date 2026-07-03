figma.showUI(__html__, { width: 420, height: 570, themeColors: true });

const NAMESPACE = "roblox_ui_bridge";
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
  return Array.isArray(object.Children) ? object.Children.filter((child) => child && child.Name) : [];
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
  node.opacity = Math.max(0, Math.min(1, Number(property(object, "GroupTransparency", 0)) === 0 ? 1 : 1 - Number(property(object, "GroupTransparency", 0))));

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
    const image = String(property(object, "Image", ""));
    node.fills = [{ type: "SOLID", color: { r: 0.88, g: 0.84, b: 1 }, opacity: Math.max(0.18, 1 - Number(property(object, "ImageTransparency", 0))) }];
    node.dashPattern = [6, 4];
    node.strokes = [{ type: "SOLID", color: { r: 0.49, g: 0.23, b: 0.93 } }];
  }

  storeMetadata(node, {
    path,
    className: object.ClassName,
    image: isImage ? String(property(object, "Image", "")) : "",
    layout: { size, pos, anchor: anch, parentWidth: parentSize.width, parentHeight: parentSize.height, managedByLayout }
  });

  if (!isText) {
    const childManagedByLayout = Boolean(childOfClass(object, "UIListLayout") || childOfClass(object, "UIGridLayout"));
    for (const child of namedChildren(object)) {
      await createVisual(child, node, `${path}/${child.Name}`, { width, height }, false, childManagedByLayout);
    }
    applyLayout(node, object);
  }
  return node;
}

function findNamed(object, name) {
  return (object.Children || []).find((child) => child.Name === name);
}

async function importModel(file) {
  const model = JSON.parse(file.text);
  const rootName = file.name.replace(/\.model\.json$/i, "").replace(/\.json$/i, "");
  const page = figma.createPage();
  page.name = `Roblox • ${rootName}`;
  await figma.setCurrentPageAsync(page);

  const viewport = { width: 1440, height: 900 };
  const modelRoot = findNamed(model, "Root") || model;
  const screens = findNamed(modelRoot, "Screens");
  const artboards = [];

  const hud = figma.createFrame();
  hud.name = `${rootName} • HUD`;
  hud.resize(viewport.width, viewport.height);
  hud.x = 0;
  hud.y = 0;
  hud.fills = [{ type: "SOLID", color: { r: 0.16, g: 0.67, b: 0.93 } }];
  hud.setSharedPluginData(NAMESPACE, "modelRoot", rootName);
  artboards.push(hud.id);

  if (screens) {
    const excluded = new Set(["ComponentTemplates", "ShowcaseCanvas", "ScreenTemplate", "Screens"]);
    for (const child of namedChildren(modelRoot)) {
      if (!excluded.has(child.Name)) await createVisual(child, hud, `${rootName}/Root/${child.Name}`, viewport, false);
    }
    let index = 0;
    for (const screen of namedChildren(screens)) {
      if (!VISUAL_CLASSES.has(screen.ClassName)) continue;
      const board = figma.createFrame();
      board.name = `${rootName} • ${screen.Name}`;
      board.resize(viewport.width, viewport.height);
      board.x = (index % 3) * (viewport.width + 120);
      board.y = (Math.floor(index / 3) + 1) * (viewport.height + 120);
      board.fills = [{ type: "SOLID", color: { r: 0.16, g: 0.67, b: 0.93 } }];
      board.setSharedPluginData(NAMESPACE, "modelRoot", rootName);
      await createVisual(screen, board, `${rootName}/Root/Screens/${screen.Name}`, viewport, true);
      artboards.push(board.id);
      index += 1;
    }
  } else {
    const prefix = modelRoot.Name === "Root" ? `${rootName}/Root` : rootName;
    for (const child of namedChildren(modelRoot)) {
      await createVisual(child, hud, `${prefix}/${child.Name}`, viewport, false);
    }
  }

  figma.currentPage.selection = page.children.filter((node) => artboards.includes(node.id));
  if (figma.currentPage.selection.length) figma.viewport.scrollAndZoomIntoView(figma.currentPage.selection);
  return artboards.length;
}

function solidPaint(node) {
  if (!("fills" in node) || !Array.isArray(node.fills)) return null;
  const paint = node.fills.find((fill) => fill.type === "SOLID");
  return paint ? { color: [paint.color.r, paint.color.g, paint.color.b], opacity: paint.opacity === undefined ? 1 : paint.opacity } : null;
}

function collectPatch(nodes) {
  const entries = [];
  const visit = (node) => {
    const path = node.getSharedPluginData ? node.getSharedPluginData(NAMESPACE, "path") : "";
    if (path) {
      const rawLayout = node.getSharedPluginData(NAMESPACE, "layout");
      const layout = rawLayout ? JSON.parse(rawLayout) : null;
      const entry = {
        path,
        className: node.getSharedPluginData(NAMESPACE, "className"),
        visible: node.visible,
        opacity: node.opacity,
        x: node.x,
        y: node.y,
        width: node.width,
        height: node.height,
        fill: solidPaint(node),
        layout
      };
      if (String(entry.className).startsWith("Text") && "children" in node) {
        const textNode = node.children.find((child) => child.type === "TEXT" && child.name === "$Text");
        entry.text = textNode ? textNode.characters : "";
        entry.fontSize = textNode && typeof textNode.fontSize === "number" ? textNode.fontSize : null;
        const textPaint = textNode ? solidPaint(textNode) : null;
        entry.textColor = textPaint ? textPaint.color : null;
      } else {
        entry.cornerRadius = typeof node.cornerRadius === "number" ? node.cornerRadius : null;
        if (Array.isArray(node.strokes)) {
          const stroke = node.strokes.find((paint) => paint.type === "SOLID");
          if (stroke) entry.stroke = { color: [stroke.color.r, stroke.color.g, stroke.color.b], thickness: node.strokeWeight };
        }
      }
      entries.push(entry);
    }
    if ("children" in node) node.children.forEach(visit);
  };
  nodes.forEach(visit);
  return entries;
}

figma.ui.onmessage = async (message) => {
  try {
    if (message.type === "close") return figma.closePlugin();
    if (message.type === "import-models") {
      let count = 0;
      for (const file of message.files || []) count += await importModel(file);
      figma.ui.postMessage({ type: "status", text: `Imported ${count} editable artboards. Image layers keep their Roblox asset IDs as metadata.` });
      return;
    }
    if (message.type === "export-patch") {
      const selected = figma.currentPage.selection.length ? figma.currentPage.selection : figma.currentPage.children;
      const entries = collectPatch(selected);
      if (!entries.length) throw new Error("Select an imported Roblox artboard first.");
      const roots = [...new Set(entries.map((entry) => entry.path.split("/")[0]))];
      const patch = { format: "roblox-ui-bridge-v1", exportedAt: new Date().toISOString(), roots, entries };
      figma.ui.postMessage({ type: "download", name: `${roots.join("-") || "roblox-ui"}.figma-patch.json`, text: JSON.stringify(patch, null, 2) });
    }
  } catch (error) {
    figma.ui.postMessage({ type: "status", text: `Error: ${error && error.message ? error.message : String(error)}` });
  }
};
