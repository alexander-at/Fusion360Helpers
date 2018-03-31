The existing dxf.cps from Autodesk does a reasonable job of generating .dxf 
files that correctly represent the path.  There are several shortcomings
that make its output cumbersome to use with LaserCut and a Chinese laser:

0) The LaserCut software only looks at color assigned to the path.  Layer
doesn't really mean anything to it for paths coming from a DXF.  The
DXF post doesn't do anything except one layer.

1) If the "Put operations in separate layers" is checked, indeed each of
the parts winds up on a different layer but they're all centered around the
same cooridinates so they're stacked on top of each other.

2) The operations come out one per layer.  A typical group of operations 
for a laser cut part is to etch/mark on the surface, cut internal features
and then cut the outline.  The per-layer grouping creates a lot of manual
work on the DXF to prepare it for the laser.

Goals / Requirements:
1) Operations should be grouped by area for each part.  In other words,
even if they're not placed optimally on a sheet, they should be easy
to select/lasso and move to a more optimal location using Adobe 
Illustrator or Inkscape.  From the perspective of Fusion 360, parts
will correspond to "Setup" for the user.  These are detectable in the
Post Processor by the characteristics of a "Section" (onSection() / 
endSection()) in the Post Processor: the 'job-description' parameter
changes to show the name of the setup.  It will stay the same for new
tools that show up through a new onSection()/endSection.  It will change
when processing moves to another setup.

Unfortunately, I don't see any advanced information about the extents
of the part in a given "Setup"'s Operations.  It seems like all of the
received geometry would need to be received, stored and analyzed in
order to figure out how big it is and how to place it into non-overlapping
2D space in some optimal way.  This leads to the stretch goal below.

2) Operations should be grouped by tool / kind of cut onto layers.  Layer
grouping makes editing and checking of them easier in the vector graphic
tools.  Operations correspond to Cutting / Milling 2D operations to the user
and to various parameters named under 'operation:tool_'.  At least two
characteristics can be used to differentiate the kind of cut: 
'operation:tool_number' parameter and the currentSection.jetMode variable.
Tool number is exposed to the user under the "Select Tool" dialog and "Edit
Tool" on "Post Processor" tab under "NC" and the "Number:" field.  The
currentSection.jetMode is exposed to the user under the "2D Profile"
configuration dialog on the "Tool" tab as "Cutting Mode".

3) Entities should have unique colors based on their layer.  This is used
by LaserCut to group different kinds of speed and power settings. 

4) Stretch: Automatically place the parts/space the parts to minimize
the area without user setup.  Stretch^2: optimize part placement for
no material waste without bad interactions between the cuts.

