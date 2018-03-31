/**
  Copyright (C) 2015-2017 by Autodesk, Inc.
  All rights reserved.
  
  Modified by A.T. Alexander for easier use with LaserCut, control
  software used by Chinese lasers.

  $Revision: 41602 8a235290846bfe71ead6a010711f4fc730f48827 $
  $Date: 2017-09-14 12:16:32 $
  
  FORKID {E251098A-758C-4C19-B8D9-8408A6BDAFC9}
*/

description = "AutoCAD DXF - With modifications to support LaserCut 5.3";
vendor = "Autodesk, with A.T. Alexander modifications.";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2015-2016 by Autodesk, Inc.";
certificationLevel = 2;

longDescription = "This post outputs the toolpath in the DXF (AutoCAD) file format. Note that the direction of the toolpath will only be preserved if you enabled the 'forceSameDirection' property which will trigger linearization of clockwise arcs. You can turn on 'onlyCutting' to get rid of the linking motion. And you can turn off 'includeDrill' to avoid points at the drilling positions. Layers will be allocated to each tool number to allow segregation of laser cut / mark / hole operations.";

capabilities = CAPABILITY_INTERMEDIATE | CAPABILITY_MILLING | CAPABILITY_JET;
extension = "dxf";
mimetype = "application/dxf";
setCodePage("utf-8");

minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = undefined; // only XY arcs

properties = {
  useTimeStamp: false,                  // enable to output a time stamp
  onlyCutting: true,                    // only output the cutting passes - ignore all linking moves
  includeDrill: true,                   // output circle for drill positions
  only2D: true,                         // only output toolpath as 2D
  forceSameDirection: false,            // enable to keep the direction of the toolpath - clockwise arcs will be linearized
  xSetupStepSize: 150,                  // mm between each "Setup" horizontally.
  xSetupStepCount: 3,                   // Number of setups in each horizontal row
  ySetupStepSize: 150,                  // mm between each "Setup" vertically
  layer: 1,                             // the lowest number layer used
  putOperationsInSeparateLayers: false  // put each operation into its own layer, regardless of tool / jetMode
};

// user-defined property definitions
propertyDefinitions = {
  useTimeStamp: {title:"Time stamp", description:"Specifies whether to output a time stamp.", type:"boolean"},
  onlyCutting: {title:"Only cutting", description:"If enabled, only cutting passes will be outputted, all linking moves will be ignored.", type:"boolean"},
  includeDrill: {title:"Include drill", description:"If enabled, circles will be output for all drill positions.", type:"boolean"},
  only2D: {title:"Output as 2D", description:"Only output toolpath as 2D.", type:"boolean"},
  forceSameDirection: {title:"Force same direction", description:"Enable to keep the direction of the toolpath, clockwise arcs will be linearized.", type:"boolean"},
  xSetupStepSize: {title:"X Setup Step Size", description:"Distance, in mm, between each Setup, horizontally", type:"integer"},
  xSetupStepCount: {title:"X Setup Step Count", description:"Number of Setups, horizontally, per row in the output", type:"integer"},
  ySetupStepSize: 150,  //mm between each "Setup" vertically
  ySetupStepSize: {title:"Y Setup Step Size", description:"Distance, in mm, between each Setup, vertically", type:"integer"},
  layer: {title:"Start Layer", description:"Sets the layer # corresponding to first operation or Tool #1.", type:"integer"},
  putOperationsInSeparateLayers: {title:"Put operations in separate layers", description:"Enable this property to put each operation on its own layer, regardless of Tool Number or Cutting Mode.", type:"boolean"}
};

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var nFormat = createFormat({decimals:9});
var angleFormat = createFormat({decimals:6, scale:DEG});

//
// Variables to manage the placement of each "Setup"
//
var xSetupStepPosition = 0;
var ySetupStepPosition = 0;
var lastJobDescription = "";
var notFirstJobDescription = false;

//
// Tame the color choices a bit...
//
var usefulColors = [
    0,  //Black
    1,  //Red
    3,  //Green
    4,  //Cyan
    5,  //Blue
    6,  //Magenta
    8,  //Dark gray
    9,  //Light gray
    11, //Pink
    20, //Dark orange
    30, //Yellowish orange
    32, //Darker yellowish orange
];

//
// Merging color usage from original Autodesk implementation, we need
// to offset the color indicies used for "movement" from those used
// based on tool.  We'll do that using some arbitrarily large number
// defined here.
var offsetIndexOfLegacyColor = 10;

//Offsets X coordinates for Setup step
function offsetXForSetupStep(rawX) {
    return rawX + (xSetupStepPosition * properties.xSetupStepSize);
}

//Offsets Y coordinates for Setup step
function offsetYForSetupStep(rawY) {
    return rawY + (ySetupStepPosition * properties.ySetupStepSize);
}

//Tames the color from an index to a nicer set of choices.
function tameColorIndex(colorIndex) {
    if(colorIndex >= usefulColors.length) {
        return colorIndex + Math.max(usefulColors)
    }
    else {
        return usefulColors[colorIndex]
    }
}

//Advances the position for the Setup step
function advanceSetupStepPosition() {
    xSetupStepPosition++;
    //See if we've pushed 'X' as far as we're allowed to.
    if(xSetupStepPosition >= properties.xSetupStepCount)
    {
      //We need to advance Y...
      ySetupStepPosition++;
      //And restart X...
      xSetupStepPosition = 0;
    }
}

/** Returns the color for the current section, based mostly on tool number but with a backup basis of jetMode. */
function getSectionColor() {
  //First try to find a tool number to get us a color
  if(hasParameter("operation:tool_number")) {
    //There's a tool number.  Use it for the color.
    return tameColorIndex(parseInt(getParameter("operation:tool_number")));
  }
  else {
    //Use the jetMode variable for the color
    return tameColorIndex(currentSection.jetMode);
  }
}

/** Returns the layer for the current section, based on tool selection or color/operation type. */
function getLayer() {
  // the layer to output into
  if (properties.putOperationsInSeparateLayers) {
    //We're ignoring tool # / jetMode for the layer.
    return properties.layer + getCurrentSectionId();
  }
  else {
    //We're using tool # / jet mode for the layer
    return properties.layer + getSectionColor() - 1;
  }
}

function onOpen() {
  //Make sure we're starting at our first x/y position offsets for the placement of each Setup.
  xSetupStepPosition = 0;
  ySetupStepPosition = 0;
  lastJobDescription = "";
  notFirstJobDescription = false;

  // use this to force unit to mm
  // xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4), scale:(unit == MM) ? 1 : 25.4});

  writeln("999");
  writeln("Generated by Autodesk CAM - http://cam.autodesk.com");

  writeln("999");
  writeln("Modifications to better support Chinese lasers and LaserCut 5.3 by A.T. Alexander");

  if (properties.useTimeStamp) {
    var d = new Date();
    writeln("999");
    writeln("Generated at " + d);
  }

  writeln("0");
  writeln("SECTION");

  writeln("2");
  writeln("HEADER");
  
  writeln("9");
  writeln("$ACADVER");
  writeln("1");
  writeln("AC1006");

  writeln("9");
  writeln("$ANGBASE");
  writeln("50");
  writeln("0"); // along +X

  writeln("9");
  writeln("$ANGDIR");
  writeln("70");
  writeln("0"); // ccw arcs
  
  writeln("0");
  writeln("ENDSEC");

  writeln("0");
  writeln("SECTION");
  writeln("2");
  writeln("BLOCKS");
  writeln("0");
  writeln("ENDSEC");

  var box = new BoundingBox(); // always includes origin
  for (var i = 0; i < getNumberOfSections(); ++i) {
    box.expandToBox(getSection(i).getGlobalBoundingBox());
  }

  writeln("9");
  writeln("$EXTMIN");
  writeln("10"); // X
  writeln(xyzFormat.format(box.lower.x));
  writeln("20"); // Y
  writeln(xyzFormat.format(box.lower.y));
  writeln("30"); // Z
  writeln(xyzFormat.format(box.lower.z));

  writeln("9");
  writeln("$EXTMAX");
  writeln("10"); // X
  writeln(xyzFormat.format(box.upper.x));
  writeln("20"); // Y
  writeln(xyzFormat.format(box.upper.y));
  writeln("30"); // Z
  writeln(xyzFormat.format(box.upper.z));

  writeln("0");
  writeln("SECTION");
  writeln("2");
  writeln("ENTITIES");
  // entities start here
}

function onComment(text) {
}

var drillingMode = false;

function onSection() {
  var remaining = currentSection.workPlane;
  if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
    error(localize("Tool orientation is not supported."));
    return;
  }
  setRotation(remaining);

  drillingMode = hasParameter("operation-strategy") && (getParameter("operation-strategy") == "drill");
  
  //Figure out if we've moved to a new setup.
  //-Get the current job description, if there is one.
  var thisJobDescription = "";
  var setupChanged = false;
  if( hasParameter("job-description")) {
    thisJobDescription = getParameter("job-description");
  }
  //-See if this is not our first job-description check...
  if(notFirstJobDescription) {
    //Is this a different job?
    if(thisJobDescription != lastJobDescription) {
      setupChanged = true;
    }
  }
  else {
    //We've seen a job description.  Remember that for the next onSection()/Setup/Operation
    notFirstJobDescription = true;
  }
  //-Record this job-description as the last job description.  If, for some reason, it's empty
  // we'll just never have a job description change.
  lastJobDescription = thisJobDescription;
  
  //-Finally, change the position offsets if we've detected that the Setup has changed
  if(setupChanged) {
    //It changed.  Move to the next x/y offset position.
    advanceSetupStepPosition();
  }

  //Find us a tool number.
  var toolNumber = "unknown";
  if(hasParameter("operation:tool_number")) {
    //There's a tool number.  Use it for the color.
    toolNumber = parseInt(getParameter("operation:tool_number"));
  }
  
  //Put some information into the DXF to map the sections and operations
  writeln("999");
  writeln("Setup: \""+thisJobDescription+"\", ToolNumber:"+toolNumber+", CuttingMode:"+currentSection.jetMode);
}

function onParameter(name, value) {
}

function onDwell(seconds) {
}

function onCycle() {
}

function onCyclePoint(x, y, z) {
  if (!properties.includeDrill) {
    return;
  }

  writeln("0");
  writeln("POINT");
  writeln("8"); // layer
  writeln(getLayer());
  writeln("62"); // color
  writeln(getSectionColor());

  writeln("10"); // X
  writeln(xyzFormat.format(offsetXForSetupStep(x)));
  writeln("20"); // Y
  writeln(xyzFormat.format(offsetYForSetupStep(y)));
  writeln("30"); // Z
  writeln(xyzFormat.format(z));
}

function onCycleEnd() {
}

function writeLine(x, y, z) {
  if (drillingMode) {
    return; // ignore since we only want points
  }

  if (radiusCompensation != RADIUS_COMPENSATION_OFF) {
    error(localize("Compensation in control is not supported."));
    return;
  }
  
  var color;
  switch (movement) {
  case MOVEMENT_CUTTING:
  case MOVEMENT_REDUCED:
  case MOVEMENT_FINISH_CUTTING:
    color = 1;
    break;
  case MOVEMENT_RAPID:
  case MOVEMENT_HIGH_FEED:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = 3;
    break;
  case MOVEMENT_LEAD_IN:
  case MOVEMENT_LEAD_OUT:
  case MOVEMENT_LINK_TRANSITION:
  case MOVEMENT_LINK_DIRECT:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = 2;
    break;
  default:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = 4;
  }

  var start = getCurrentPosition();
  if (properties.only2D) {
    if ((xyzFormat.format(start.x) == xyzFormat.format(x)) &&
        (xyzFormat.format(start.y) == xyzFormat.format(y))) {
      return; // ignore vertical
    }
  }

  writeln("0");
  writeln("LINE");
  writeln("8"); // layer
  writeln(getLayer());
  writeln("62"); // color
  if(color != 1)
  {
    //Offset the movement based color by an arbitrarily largish number
    writeln(color+offsetIndexOfLegacyColor);
  }
  else {
    writeln(getSectionColor());
  }

  writeln("10"); // X
  writeln(xyzFormat.format(offsetXForSetupStep(start.x)));
  writeln("20"); // Y
  writeln(xyzFormat.format(offsetYForSetupStep(start.y)));
  writeln("30"); // Z
  writeln(xyzFormat.format(properties.only2D ? 0 : start.z));

  writeln("11"); // X
  writeln(xyzFormat.format(offsetXForSetupStep(x)));
  writeln("21"); // Y
  writeln(xyzFormat.format(offsetYForSetupStep(y)));
  writeln("31"); // Z
  writeln(xyzFormat.format(properties.only2D ? 0 : z));
}

function onRapid(x, y, z) {
  writeLine(x, y, z);
}

function onLinear(x, y, z, feed) {
  writeLine(x, y, z);
}

function onRapid5D(x, y, z, dx, dy, dz) {
  onRapid(x, y, z);
}

function onLinear5D(x, y, z, dx, dy, dz, feed) {
  onLinear(x, y, z);
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (getCircularPlane() != PLANE_XY) {
    // start and end angle reference is unknown
    linearize(tolerance);
    return;
  }

  if (clockwise && properties.forceSameDirection) {
    linearize(tolerance);
    return;
  }

  if (properties.only2D) {
    if (getCircularPlane() != PLANE_XY) {
      linearize(tolerance);
      return;
  }
  }

  if (radiusCompensation != RADIUS_COMPENSATION_OFF) {
    error(localize("Compensation in control is not supported."));
    return;
  }

  var color;
  switch (movement) {
  case MOVEMENT_CUTTING:
  case MOVEMENT_REDUCED:
  case MOVEMENT_FINISH_CUTTING:
    color = 1;
    break;
  case MOVEMENT_RAPID:
  case MOVEMENT_HIGH_FEED:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = 3;
    break;
  case MOVEMENT_LEAD_IN:
  case MOVEMENT_LEAD_OUT:
  case MOVEMENT_LINK_TRANSITION:
  case MOVEMENT_LINK_DIRECT:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = 2;
    break;
  default:
    if (properties.onlyCutting) {
      return; // skip
    }
    color = 4;
  }

  writeln("0");
  writeln("ARC");
  writeln("8"); // layer
  writeln(getLayer());
  writeln("62"); // color
  if(color != 1)
  {
    //Offset the movement based color by an arbitrarily largish number
    writeln(color+offsetIndexOfLegacyColor);
  }
  else {
    writeln(getSectionColor());
  }

  writeln("10"); // X
  writeln(xyzFormat.format(offsetXForSetupStep(cx)));
  writeln("20"); // Y
  writeln(xyzFormat.format(offsetYForSetupStep(cy)));
  writeln("30"); // Z
  writeln(xyzFormat.format(properties.only2D ? 0 : cz));

  writeln("40"); // radius
  writeln(xyzFormat.format(getCircularRadius()));

  var start = getCurrentPosition();
  var startAngle = Math.atan2(start.y - cy, start.x - cx);
  var endAngle = Math.atan2(y - cy, x - cx);
  // var endAngle = startAngle + (clockwise ? -1 : 1) * getCircularSweep();
  if (clockwise) { // we must be ccw
    var temp = startAngle;
    startAngle = endAngle;
    endAngle = temp;
  }
  writeln("50"); // start angle
  writeln(angleFormat.format(startAngle));
  writeln("51"); // end angle
  writeln(angleFormat.format(endAngle));
  
  if (getCircularPlane() != PLANE_XY) {
  validate(!properties.only2D, "Invalid handling on onCircular().");
    var n = getCircularNormal();
    writeln("210"); // X
    writeln(nFormat.format(offsetXForSetupStep(n.x)));
    writeln("220"); // Y
    writeln(nFormat.format(offsetYForSetupStep(n.y)));
    writeln("230"); // Y
    writeln(nFormat.format(n.z));
  }
}

function onCommand() {
}

function onSectionEnd() {
}

function onClose() {
  writeln("0");
  writeln("ENDSEC");
  writeln("0");
  writeln("EOF");
}
