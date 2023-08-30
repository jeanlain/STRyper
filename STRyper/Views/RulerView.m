//
//  RulerView.m
//  STRyper
//
//  Created by Jean Peccoud on 24/01/13.
//  Copyright (c) 2013 Jean Peccoud. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.



#import "RulerView.h"
#import "TraceScrollView.h"
#import "FittingView.h"
#import "RegionLabel.h"
#import "MarkerView.h"

const float ruleThickness = 14.0;			/// the thickness of the ruler

static NSCursor *loupeCursor;

/// we prepare an array of labels used for the ruler (expressed in base pairs), which is shared by all ruler views.
/// Possible improvement: all strings we show could be in CATextLayers, which would be moved around by the GPU when the trace view scrolls, instead of redrawing everything.
/// however, creating one layer for every label (> 1000 possible sizes in base pairs) would be too much,
/// so we would have to recycle labels, which would make the code a bit more complex
static NSArray <NSAttributedString *> *sizeArray;

/// same as above, but with a different text color to represent sizes within the range of a maker that has an offset
static NSArray <NSAttributedString *> *sizeArrayRed;

/// these arrays will store the with an height of each string to avoid recomputing them at every drawRect
static float labelWidth[MAX_TRACE_LENGTH +1], labelHeight[MAX_TRACE_LENGTH +1];
static NSColor *tickmarckColor;


/// strings that can be displayed if the sample shown by the traceView is not sized
/// they replaces the labels in the display
static NSAttributedString *noSizing;			/// when no size standard is applied
static NSAttributedString *failedSizing;
static float noSizingWidth;						/// we will compute their width just once. We use it to center these strings in the view.
static float failedSizingWidth;

/// the layer showing the current position of the mouse using a vertical line. We use a global instance as only one view at a time shows this layer
static CALayer *currentPositionMarkerLayer;
static CATextLayer *currentPositionLayer;		/// the layer showing the current position in base pairs


@implementation RulerView {
	
	NSPoint mouseLocation;
	BOOL isDraggingForZoom;        		/// tells if the user is performing a zoom by dragging the mouse
	float startPoint;   				/// the location of the last mouseDown event, used to compute the area that is covered by a mouse drag
	float startSize;
	NSTimeInterval timeStamp;    		/// the timestamp of the last mouseDown event, to avoid zooming by a simple click
	__weak TraceView *traceView; 		/// the traceView associated with this view
	float *offsets;						/// allow side labels to show at the correct position in the range of a marker, considering its offset
	NSMenu *menu;						/// the view's contextual menu (allowing to zoom to the default range)
	NSTimeInterval startScrollTime;		/// The start time of a scroll action, which we use to interpret a swipe event
	float horizontalScrollAmount;
}


/// Implementation notes:
/// The drawing of size labels is done in -drawRect:
/// This class doesn't use any draw method of NSRulerView because the labels must be repositioned when zooming (the magnification factor of the scrollview cannot be used on our case, see TraceScrollView.h).
/// Hence, this class use other NSRulerView methods. It only uses the fact that NSRulerView is positioned at the right place for a horizontal ruler, and that it redraws when the document view scrolls.


#pragma mark - initialization and general attributes

+ (void)initialize {
	NSImage *cursorImage = [NSImage imageNamed:@"loupeCursorBordered"];
	cursorImage.size = NSMakeSize(15, 20);
	loupeCursor = [[NSCursor alloc]initWithImage:cursorImage hotSpot:NSMakePoint(6.1, 5.9)];
	
	tickmarckColor = NSColor.grayColor;
	
	extern NSDictionary *gLabelFontStyle;
	NSDictionary *redFontStyle = @{NSFontAttributeName: [NSFont labelFontOfSize:8.0],
								   NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0 green:0.2 blue:0.2 alpha:1]};

	/// we populate the label array. We do it once for all rulerViews.
	NSMutableArray *temp = NSMutableArray.new;
	NSMutableArray *tempRed = NSMutableArray.new;
	for(int size = 0; size <= MAX_TRACE_LENGTH; size++) {
		NSAttributedString *rulerLabel = [[NSAttributedString alloc]initWithString:[NSString stringWithFormat:@"%d", size] attributes:gLabelFontStyle];
		NSAttributedString *rulerLabelRed = [[NSAttributedString alloc]initWithString:[NSString stringWithFormat:@"%d", size] attributes:redFontStyle];

		
		/// we also compute the dimension of labels now, once for all, as it can be costly to do on the fly
		labelWidth[size] = rulerLabel.size.width;
		labelHeight[size] = rulerLabel.size.height;  /// which is actually the same for all labels, but we do it anyway
		[temp addObject:rulerLabel];
		[tempRed addObject:rulerLabelRed];
		
	}
	sizeArray = [NSArray arrayWithArray:temp];
	sizeArrayRed = [NSArray arrayWithArray:tempRed];

	NSDictionary *fontAttributes = @{NSFontAttributeName: [NSFont labelFontOfSize:10], NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
	
	noSizing = [[NSAttributedString alloc]initWithString:@"No size standard applied" attributes:fontAttributes];
	failedSizing = [[NSAttributedString alloc]initWithString:@"Sample sizing failed" attributes:fontAttributes];
	noSizingWidth = noSizing.size.width;
	failedSizingWidth = failedSizing.size.width;

	
	/// we initialize the layers that show the current mouse position
	/// the base layer only shows a vertical line at the position
	currentPositionMarkerLayer = CALayer.new;
	currentPositionMarkerLayer.backgroundColor = tickmarckColor.CGColor;
	currentPositionMarkerLayer.anchorPoint = CGPointMake(1, 1);
	currentPositionMarkerLayer.opaque = YES;
	currentPositionMarkerLayer.actions = @{@"position": NSNull.null};
	currentPositionMarkerLayer.bounds = CGRectMake(0, 0, 1, ruleThickness);

	currentPositionLayer = CATextLayer.new;
	currentPositionLayer.contentsScale = 2.0;								/// this makes text sharper even on a non-retina display
	currentPositionLayer.bounds = CGRectMake(0, 0, 25, 14);					/// this ensures that the layer hides the ruler labels and tick-marks behind it (25 is larger than any string it can show)
	currentPositionLayer.anchorPoint = CGPointMake(0, 0);
	currentPositionLayer.font = (__bridge CFTypeRef _Nullable)(gLabelFontStyle[NSFontAttributeName]);
	currentPositionLayer.fontSize = 8.0;
	currentPositionLayer.allowsFontSubpixelQuantization = YES;
	currentPositionLayer.actions = @{@"position": NSNull.null, @"string": NSNull.null, @"bounds": NSNull.null};
	
	[currentPositionMarkerLayer addSublayer:currentPositionLayer];
	currentPositionLayer.position = CGPointMake(1, 2);		/// this places this layer 1 pixel to the right of the vertical line of the currentPositionMarkerLayer
	
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		/*
		NSButton *button = [NSButton buttonWithImage:[NSImage imageNamed:@"zoomToFit"] target:self action:@selector(zoomToFit:)];
		button.bezelStyle = NSBezelStyleInline;
		button.bordered = NO;
		button.imagePosition = NSImageOnly;
		button.imageScaling = NSImageScaleNone;
		[button.cell setBackgroundColor: NSColor.windowBackgroundColor];
		button.frame = NSMakeRect(-25, 20, 20, ruleThickness);
		button.toolTip = @"Zoom to default range";
		button.autoresizingMask = NSViewMaxXMargin;
		[self addSubview:button]; */
		
		/// we initialize the offset. There is one per size label.
		offsets = calloc(MAX_TRACE_LENGTH, sizeof(float));
	}
	return self;
}



- (BOOL)isOpaque {
	return YES;
}


- (NSInteger)tag {
	return 4;
}


- (BOOL)acceptsFirstMouse:(NSEvent *)event{
	return YES;
}


- (BOOL)wantsLayer {
	return YES;
}


- (void)setHidden:(BOOL)hidden {
	super.hidden = hidden;
	[traceView fitVertically];
}


- (void)setClientView:(NSView *)clientView {
	super.clientView = clientView;
	traceView = (TraceView *)clientView;
}


- (void)updateTrackingAreas {
	
	[super updateTrackingAreas];
}


#pragma mark - indicating positions


- (void)setNeedsUpdateOffsets:(BOOL)needsUpdateOffsets {
	_needsUpdateOffsets = needsUpdateOffsets;
	self.needsDisplay = YES;
}


- (void)updateOffsets {
	free(offsets);
	///  there is one offset per size label. It indicates the shift in base pairs compared to the position without offset.
	offsets = calloc(MAX_TRACE_LENGTH, sizeof(float));
	for(RegionLabel *markerLabel in traceView.markerLabels) {
		float intercept = markerLabel.offset.intercept;
		float slope = markerLabel.offset.slope;
		if(slope == 1.0 && intercept == 0.0) {
			continue;
		}
		int start = (int)(markerLabel.start + 0.9);
		if(start < 0) {
			start = 0;
		}
		int end =  (int)(markerLabel.end);
		if(end > MAX_TRACE_LENGTH) {
			end = MAX_TRACE_LENGTH;
		}
		for (int i = start; i < end; i++) {
			float newI = (float)i * slope + intercept;
			if(newI < start || newI > end) {
				offsets[i] = -1000.0;		/// this will denote that size label at index i should not be drawn, to avoid overlap
				continue;
			}
			offsets[i] = newI - (float)i;
		}
	}
}


- (void)setCurrentPosition:(float)position {
	if(traceView.trace && traceView.trace.chromatogram.sizingQuality == nil) {
		if(_currentPosition <= -1000) {
			/// if the sample is not sized, we make sure the current position layer does not show
			return;
		}
		position = -1000;
	}
	
	int i = round(position);
	float positionToShow = position;
	
	/// we need to consider the offset of a marker in which the position may lie
	if(i > 0 && i < MAX_TRACE_LENGTH) {
		float offset = offsets[i];
		if(offset > -999) {			/// -1000 is an offset to ignore
			positionToShow -= offset;
		}
	}
	
	_currentPosition = position;
	
	if(currentPositionMarkerLayer.superlayer != self.layer) {
		if(position < traceView.sampleStartSize) {
			/// we don't update the layer if the position cannot be visible anyway
			/// But if the layer is in another view, it may means the mouse has entered that view already, so we don't do move the layer
			return;
		}
		if(currentPositionLayer.superlayer != self.layer) {
			/// a single layer is used for all instances, so we need to make it ours
			[self.layer addSublayer:currentPositionMarkerLayer];
			
			/// maybe it's because the layer is moved between views, but its text sometimes becomes white and cannot be read in light mode.
			/// Setting the label's color when we acquire it appears to eliminate the issue
			self.needsChangeAppearance = YES;
		}
	}
	currentPositionLayer.string = [NSString stringWithFormat:@"%.01f", positionToShow];
	float pos = [self xForSize:position];
	currentPositionMarkerLayer.position = CGPointMake(pos, NSMaxY(self.bounds));
}


- (void)setNeedsChangeAppearance:(BOOL)needsChangeAppearance{
	/// viewDidChangeEffectiveAppearance is not adequate because this would no be called on ruler view that are in the reuse queue of a tableview. 
	_needsChangeAppearance = needsChangeAppearance;
	if(needsChangeAppearance) {
		self.needsDisplay = YES;
	}
}

/// returns the increment between consecutive size labels to show, considering the horizontal scale of the traceView
- (int)rulerLabelIncrement {
	float hScale = traceView.hScale;
	if(hScale > 50) {
		return 1;
	}
	if (hScale > 10) {
		return 5;
	}
	if (hScale > 2) {
		return 25;
	}
	return 50;
}


- (void)drawRect:(NSRect)dirtyRect {
	if(_needsUpdateOffsets) {
		[self updateOffsets];
		self.needsUpdateOffsets = NO;
	}
	
	[NSColor.windowBackgroundColor setFill];
	NSRectFill(dirtyRect);
	/* // to possibly show offscale regions on the ruler (test)
	Chromatogram *sample = traceView.trace.chromatogram;
	const float *sizes = sample.sizes.bytes;
	extern NSArray *gNSColorsForChannels;

	if (sample.offscaleRegions.length > 0 && ![NSUserDefaults.standardUserDefaults boolForKey:ShowOffScale] && traceView.loadedTraces.count == 1) {
		const OffscaleRegion *regions = sample.offscaleRegions.bytes;
		for (int i = 0; i < sample.offscaleRegions.length/sizeof(OffscaleRegion); i++) {
			OffscaleRegion region = regions[i];
			float regionStart = sizes[region.startScan];
			float regionEnd = sizes[region.endScan+1];
		//	if (regionEnd >= startSize && regionStart <= endSize) {
				NSColor *color = gNSColorsForChannels[region.dye];
				[color setFill];
				float x1 = [self xForSize:regionStart];
				float x2 = [self xForSize:regionEnd];
				NSRectFill(NSMakeRect(x1, NSMaxY(self.bounds)-3, x2-x1, NSMaxY(self.bounds)));
		//	}
		}
	}  */

	if (isDraggingForZoom) {
		/// draws dragging selection as a grey rectangle (for zooming)
		[NSColor.secondaryLabelColor setFill];
		float startSizeX = [self xForSize:startSize];
		NSBezierPath *selection = [NSBezierPath bezierPathWithRect:NSMakeRect(startSizeX, NSMaxY(self.bounds)-3, mouseLocation.x - startSizeX, NSMaxY(self.bounds))];
		[selection fill];
	}
	
	Chromatogram *sample = traceView.trace.chromatogram;
	
	if(sample && sample.sizingQuality == nil) {
		if(!sample.sizeStandard) {
			[noSizing drawAtPoint: NSMakePoint(NSMidX(self.bounds) - noSizingWidth/2, NSMaxY(self.bounds)-15)];
		} else {
			[failedSizing drawAtPoint: NSMakePoint(NSMidX(self.bounds) - failedSizingWidth/2, NSMaxY(self.bounds)-15)];
		}
		return;
	}
	
	/// we draw ruler of sizes in base pairs at the top of the view
	int labelIncrement = [self rulerLabelIncrement];
	
	/// we determine the range of sizes in the dirty rectangle
	float startX = dirtyRect.origin.x;
	if (startX < 0) {
		startX = 0;
	}
	float startSize = [self sizeForX:startX] ;
	float endSize = startSize + dirtyRect.size.width / traceView.hScale +1;
	
	if(endSize > MAX_TRACE_LENGTH) {
		endSize = MAX_TRACE_LENGTH;
	}
	
	for (int size=0; size <= endSize; size+=labelIncrement) {
		/// we cannot start at startSize since it's a float and size must be an index, and we need to start at a given increment
		float offset= offsets[size];
		if(offset <= -1000.0) {
			continue;
		}
		float x = [self xForSize:size + offset];
		
		/// We avoid  drawing on top of the vertical ruler (i.e., at negative x position)
		if(size + labelWidth[size]/2 >= startSize && x >= -1) {
																						
			NSAttributedString *rulerLabel =  offset == 0? sizeArray[size] : sizeArrayRed[size];
			NSPoint origin = NSMakePoint(x- labelWidth[size]/2, NSMaxY(self.bounds) - labelHeight[size] -2);
			
			[rulerLabel drawAtPoint:origin];
			[tickmarckColor setStroke];
			[NSBezierPath strokeLineFromPoint:NSMakePoint(x, NSMaxY(self.bounds)-3) toPoint:NSMakePoint(x, NSMaxY(self.bounds))]; /// little tick-mark
			
		}
	}
	
	if(self.needsChangeAppearance) {
		currentPositionLayer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
		currentPositionLayer.foregroundColor = NSColor.secondaryLabelColor.CGColor;
		self.needsChangeAppearance = NO;
	}
	
}


- (float)sizeForX:(float)x {
	return (traceView.visibleOrigin + x) / traceView.hScale + traceView.sampleStartSize;
}


- (float)xForSize:(float)size {
	return (size - traceView.sampleStartSize) * traceView.hScale - traceView.visibleOrigin;
}


#pragma mark - zooming-related methods


- (void)resetCursorRects {
	[self addCursorRect:self.visibleRect cursor:loupeCursor];
	
}

const NSBindingName AllowSwipeBetweenMarkersBinding = @"allowSwipeBetweenMarkers";


- (void)scrollWheel:(NSEvent *)event {
	if(!self.allowSwipeBetweenMarkers) {
		[super scrollWheel:event];
		return;
	}
	
	float delta = event.scrollingDeltaX;
	if(fabs(delta) < fabs(event.scrollingDeltaY)) {
		[super scrollWheel:event];
		return;
	}
	
	/// if the user scrolls rapidly to the left or right, we interpret the event as a swipe, to move between markers
	MarkerView *markerView = (MarkerView *)self.accessoryView;
	if(![markerView respondsToSelector:@selector(markerLabels)] || markerView.markerLabels.count == 0) {
		/// We do a standard scroll if there is no marker view or if it doesn't show any marker
		[super scrollWheel:event];
		return;
	}
	
	if(event.phase == NSEventPhaseBegan) {
		horizontalScrollAmount = delta;
		startScrollTime = event.timestamp;
	} else if(event.phase == NSEventPhaseEnded) {
		float timeTaken = event.timestamp - startScrollTime;
		if(timeTaken < 0.5 && fabsf(horizontalScrollAmount) > 40.0) {
			if(horizontalScrollAmount > 0) {
				[markerView moveToPreviousMarker:self];
			} else {
				[markerView moveToNextMarker:self];
			}
		}
		startScrollTime = 0;
	} else {
		if(startScrollTime > 0) {
			horizontalScrollAmount += delta;
		} else {
			/// in this case, the user must have a standard mouse (there was not start phase)
			[super scrollWheel:event];
		}
	}
}


- (void)mouseDown:(NSEvent *)theEvent   {
	[loupeCursor set];
	mouseLocation= [self convertPoint:theEvent.locationInWindow fromView:nil];
	startPoint = mouseLocation.x;
	startSize = [self sizeForX:startPoint];
	/// we record the time of the click, as we don't zoom for the first click of a double-click sequence (in case the user has dragged the mouse slightly)
	timeStamp = theEvent.timestamp;
}


- (void)mouseDragged:(NSEvent *)theEvent   {
	mouseLocation = [self convertPoint:theEvent.locationInWindow fromView:nil];
	[self autoscrollWithLocation: mouseLocation];
	isDraggingForZoom = YES;
	self.needsDisplay = YES;
}


- (void)autoscrollWithLocation:(NSPoint)location {
	/// if the mouse is dragged beyond our bounds (in the x dimension), we make the traceView scroll
	float delta = location.x ;
	if(delta < 0) {	/// the mouse has passed the left limit
		if(traceView.visibleOrigin + delta < 0) {
			return;	/// this would scroll the traceView too far the right
		}
	} else {
		delta = location.x - NSMaxX(self.bounds);
		if(delta > 0) {	/// the mouse has passed the right limit
			float newOrigin = traceView.visibleOrigin + delta;
			if(newOrigin + traceView.visibleRect.size.width > NSMaxX(traceView.bounds)) {
				return;
			}
		} else {
			return;	/// here, the mouse is within the limits, we don't need to scroll
		}
	}
	
	BaseRange newRange = traceView.visibleRange;
	newRange.start += delta/traceView.hScale;
	traceView.visibleRange = newRange;	
}


- (void)mouseUp:(NSEvent *)theEvent {
	[loupeCursor set];
	if (theEvent.clickCount == 2) {  /// we zoom out to the default when the user double clicks
		if (traceView.marker) {
			[traceView zoomToMarker];
			return;
		}
		[self zoomToFit:self];
		return;
	}
	if (isDraggingForZoom) {               				/// if the mouse has been dragged, we may zoom to the selected region
		isDraggingForZoom = NO;
		if((theEvent.timestamp - timeStamp > 0.2 && fabs(startPoint - mouseLocation.x) > 3) || fabs(startPoint - mouseLocation.x) > 10) { ; 	/// we do not zoom if this appears to be a simple click (of a double click sequence)
			[traceView zoomFromSize:startSize toSize:[self sizeForX:mouseLocation.x]];
		}
		self.needsDisplay = YES;  						/// eve if the zoom did not occur (which tiggers a redisplay) we need to clear the selection rectangle
	}
}


-(void)zoomToFit:(id)sender {
	[traceView zoomFromSize:[NSUserDefaults.standardUserDefaults doubleForKey:DefaultStartSize]
					 toSize:[NSUserDefaults.standardUserDefaults doubleForKey:DefaultEndSize]];
}


-(NSMenu *)menu {
	if(!menu) {
		menu = NSMenu.new;
		[menu addItemWithTitle:@"Zoom to Default Range" action:@selector(zoomToFit:) keyEquivalent:@""];
		menu.itemArray.lastObject.target = self;
	}
	return menu;
}

# pragma mark - other

- (void)dealloc {
	free(offsets);
}

@end

