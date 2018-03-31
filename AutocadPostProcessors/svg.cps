/**
  Copyright (C) 2015-2016 by Autodesk, Inc.
  All rights reserved.

  $Revision: 41601 2e6200651f01fad70bd72491303b9729cd57fc6e $
  $Date: 2017-09-14 12:02:56 $
  
  FORKID {1B86A6B2-1294-4C75-A1DF-99A06992A163}
*/

description = "SVG in HTML";
vendor = "Autodesk";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2015-2016 by Autodesk, Inc.";
certificationLevel = 2;

longDescription = "Example post illustrating how to convert the toolpath into SVG embedded in HTML.";

capabilities = CAPABILITY_INTERMEDIATE;
extension = "html";
mimetype = "text/html";
setCodePage("utf-8");

minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(90); // avoid potential center calculation errors for CNC
allowHelicalMoves = true;
allowedCircularPlanes = (1 << PLANE_XY); // only XY arcs

properties = {
  useTimeStamp: false, // enable to output a time stamp
  onlyCutting: false, // only output the cutting passes - ignore all linking moves
  includeDrill: true, // output circle for drill positions
  includeDwell: true, // output filled red circle for dwell positions
  includeWorkpiece: true, // output box for the workpiece
  includeOrigin: true, // show origin
  format: "a4" // use letter or a4 - choose automatically from unit if not set
};

// user-defined property definitions
propertyDefinitions = {
  useTimeStamp: {title:"Output timestamp", description:"Enable to output a timestamp.", type:"boolean"},
  onlyCutting: {title:"Only cutting", description:"If enabled, only cutting passes will be outputted, all linking moves will be ignored.", type:"boolean"},
  includeDrill: {title:"Include drill", description:"If enabled, circles will be output for all drill positions.", type:"boolean"},
  includeDwell: {title:"Include dwell", description:"Enable to output a red circle for dwell positions.", type:"boolean"},
  includeWorkpiece: {title:"Output workpiece", description:"Enable to output a box for the workpiece.", type:"boolean"},
  includeOrigin: {title:"Show origin", description:"Enable to show the origin in the SVG.", type:"boolean"},
  format: {title:"Format", description:"Sets the formatting of the SVG.", type:"enum", values:["a4", "letter"]}
};

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});

/** Returns the given spatial value in MM. */
function toMM(value) {
  return value * ((unit == IN) ? 25.4 : 1);
}

function onOpen() {
  writeln("<!DOCTYPE html>");
  writeln("<html>");
  writeln("<head><title>" + (programName ? programName : localize("Unnamed")) + " - Autodesk CAM" + "</title></head>");
  writeln("<body>");
  writeln("<!-- http://cam.autodesk.com -->");
  if (properties.useTimeStamp) {
    var d = new Date();
    writeln("<!-- " + (d.getTime() * 1000) + " -->");
  }

  // Letter paper size (215.9 × 279.4 millimeters or 8 1/2 × 11 inches)

  var WIDTH = 210;
  var HEIGHT = 297;

  var format = properties.format.toLowerCase();
  if (!format) {
    format = (unit == IN) ? "letter" : "a4";
  }
  switch (format) {
  case "a4":
    WIDTH = 210;
    HEIGHT = 297;
    break;
  case "letter":
    WIDTH = 215.9;
    HEIGHT = 279.4;
    break;
  default:
    warning(localize("Unsupported output format. Using A4."));
  }

  var box = getWorkpiece();
  var dx = toMM(box.upper.x - box.lower.x);
  var dy = toMM(box.upper.y - box.lower.y);

  log("Width: " + xyzFormat.format(dx));
  log("Height: " + xyzFormat.format(dy));

  var width = WIDTH;
  var height = HEIGHT;

  var useLandscape = false;
  if ((dx > width) || (dy > height)) {
    if ((dx <= height) && (dy <= width)) {
      useLandscape = true;
      width = HEIGHT;
      height = WIDTH;
    }
  }

  log("Paper width: " + xyzFormat.format(width));
  log("Paper height: " + xyzFormat.format(height));

  if (dx > width) {
    warning(localize("Toolpath exceeds paper width."));
  }
  if (dy > height) {
    warning(localize("Toolpath exceeds paper height."));
  }

  writeln("<svg width=\"" + xyzFormat.format(width) + "mm\" height=\"" + xyzFormat.format(height) + "mm\" viewBox=\"0 0 " + xyzFormat.format(width) + " " + xyzFormat.format(height) + "\">");

  // background
  // writeln("<rect x=\"" + xyzFormat.format(0) + "\" y=\"" + xyzFormat.format(0) + "\" width=\"" + xyzFormat.format(width) + "\" height=\"" + xyzFormat.format(height) + "\" style=\"fill:magenta;stroke:black;stroke-width:1;fill-opacity:0.1;stroke-opacity:0.25\"/>");

  // invert y axis
  writeln("<g transform=\"translate(" + xyzFormat.format(0) + ", " + xyzFormat.format(height) + ")\">");
  writeln("<g transform=\"scale(1, -1)\">");

  // center on page
  writeln("<g transform=\"translate(" + xyzFormat.format(-toMM(box.lower.x) + (width - dx)/2) + ", " + xyzFormat.format(-toMM(box.lower.y) + (height - dy)/2) + ")\">");

  if (properties.includeWorkpiece) {
    writeln("<rect x=\"" + xyzFormat.format(box.lower.x) + "\" y=\"" + xyzFormat.format(box.lower.y) + "\" width=\"" + xyzFormat.format(dx) + "\" height=\"" + xyzFormat.format(dy) + "\" style=\"fill:gray;stroke:black;stroke-width:1;fill-opacity:0.1;stroke-opacity:0.25\"/>");
  }

  if (properties.includeOrigin) {
    writeln("<circle cx=\"" + xyzFormat.format(0) + "\" cy=\"" + xyzFormat.format(0) + "\" r=\"" + 2.5 + "\" style=\"fill:black;stroke:black;stroke-width:1;fill-opacity:0.1;stroke-opacity:0.9\"/>");
  }

  // we output in mm always so scale from inches
  xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4), scale:(unit == MM) ? 1 : 25.4});
}

function onComment(text) {
}

function onSection() {
  var remaining = currentSection.workPlane;
  if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
    error(localize("Tool orientation is not supported."));
    return;
  }
  setRotation(remaining);
}

function onParameter(name, value) {
}

function onDwell(seconds) {
  if (!properties.includeDwell) {
    return;
  }

  var color = "black";
  var width = 1;
  var radius = tool.diameter * 0.5;
  writeln("<circle cx=\"" + xyzFormat.format(x) + "\" cy=\"" + xyzFormat.format(y) + "\" r=\"" + xyzFormat.format(radius) + "\" stroke=\"" + color + "\" stroke-width=\"" + width + "\" fill=\"red\"/>");
}

function onCycle() {
}

function onCyclePoint(x, y, z) {
  if (!properties.includeDrill) {
    return;
  }

  var color = "green";
  var width = 1;
  var radius = tool.diameter * 0.5;
  writeln("<circle cx=\"" + xyzFormat.format(x) + "\" cy=\"" + xyzFormat.format(y) + "\" r=\"" + xyzFormat.format(radius) + "\" stroke=\"" + color + "\" stroke-width=\"" + width + "\"/>");
}

function onCycleEnd() {
}

function writeLine(x, y) {
  if (radiusCompensation != RADIUS_COMPENSATION_OFF) {
    error(localize("Compensation in control is not supported."));
    return;
  }
  
  var color;
  switch (movement) {
  case MOVEMENT_CUTTING:
  case MOVEMENT_REDUCED:
  case MOVEMENT_FINISH_CUTTING:
    color = "blue";
    break;
  case MOVEMENT_RAPID:
  case MOVEMENT_HIGH_FEED:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = "yellow";
    break;
  case MOVEMENT_LEAD_IN:
  case MOVEMENT_LEAD_OUT:
  case MOVEMENT_LINK_TRANSITION:
  case MOVEMENT_LINK_DIRECT:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = "green";
    break;
  default:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = "red";
  }

  var width = 1; // use different width for etching and cutting
  var start = getCurrentPosition();
  if ((xyzFormat.format(start.x) == xyzFormat.format(x)) &&
      (xyzFormat.format(start.y) == xyzFormat.format(y))) {
    return; // ignore vertical
  }
  writeln("<line x1=\"" + xyzFormat.format(start.x) + "\" y1=\"" + xyzFormat.format(start.y) + "\" x2=\"" + xyzFormat.format(x) + "\" y2=\"" + xyzFormat.format(y) + "\" stroke=\"" + color + "\" stroke-width=\"" + width + "\"/>");
}

function onRapid(x, y, z) {
  writeLine(x, y);
}

function onLinear(x, y, z, feed) {
  writeLine(x, y);
}

function onRapid5D(x, y, z, dx, dy, dz) {
  onRapid(x, y, z);
}

function onLinear5D(x, y, z, dx, dy, dz, feed) {
  onLinear(x, y, z);
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  // linearize(tolerance);
  // return;

  if (radiusCompensation != RADIUS_COMPENSATION_OFF) {
    error(localize("Compensation in control is not supported."));
    return;
  }
  
  var color;
  switch (movement) {
  case MOVEMENT_CUTTING:
  case MOVEMENT_REDUCED:
  case MOVEMENT_FINISH_CUTTING:
    color = "blue";
    break;
  case MOVEMENT_RAPID:
  case MOVEMENT_HIGH_FEED:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = "yellow";
    break;
  case MOVEMENT_LEAD_IN:
  case MOVEMENT_LEAD_OUT:
  case MOVEMENT_LINK_TRANSITION:
  case MOVEMENT_LINK_DIRECT:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = "green";
    break;
  default:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = "red";
  }

  var width = 1; // use different width for etching and cutting
  var start = getCurrentPosition();

  var largeArc = (getCircularSweep() > Math.PI) ? 1 : 0;
  var sweepFlag = isClockwise() ? 0 : 1;
  var d = [
    "M", xyzFormat.format(start.x), xyzFormat.format(start.y),
    "A", xyzFormat.format(getCircularRadius()), xyzFormat.format(getCircularRadius()), 0, largeArc, sweepFlag, xyzFormat.format(x), xyzFormat.format(y)
  ].join(" ");
  writeln("<path d=\"" + d + "\" fill=\"none\" stroke=\"" + color + "\" stroke-width=\"" + width + "\"/>");
}

function onCommand() {
}

function onSectionEnd() {
}

function onClose() {
  writeln("</g>");
  writeln("</g>");
  writeln("</g>");
  writeln("</svg>");
  writeln("</body>");
  writeln("</html>");
}
