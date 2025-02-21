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
#import "RegionLabel.h"
#import "MarkerView.h"

const float ruleThickness = 14.0;			/// the thickness of the ruler

/// Variables that manage the loupe cursors
static NSCursor *loupeCursor;
static NSCursor *loupeCursorMinus; /// indicates that one can zoom out.
static id eventMonitor;			   /// to monitor when the alt key is pressed, for zooming out.

/// we prepare an array of labels used for the ruler (expressed in base pairs), which is shared by all ruler views.
/// Possible improvement: all strings we show could be in CATextLayers, which would be moved around by the GPU when the trace view scrolls, instead of redrawing everything.
/// however, creating one layer for every label (> 1000 possible sizes in base pairs) would be too much,
/// so we would have to recycle labels, which would make the code a bit more complex
static NSArray <NSAttributedString *> *sizeArray;

/// same as above, but with a different text color to represent sizes within the range of a maker that has an offset
static NSArray <NSAttributedString *> *sizeArrayRed;

/// these arrays will store the with an height of each string to avoid recomputing them at every drawRect
static float labelWidth[MAX_TRACE_LENGTH +1], labelHeight[MAX_TRACE_LENGTH +1];

static void * const sampleSizeStandardChangedContext = (void*)&sampleSizeStandardChangedContext;


/// strings that can be displayed if the sample shown by the traceView is not sized
/// they replaces the labels in the display
static NSAttributedString *noSizing;			/// when no size standard is applied
static NSAttributedString *failedSizing;
static float noSizingWidth;						/// we will compute their width just once. We use it to center these strings in the view.
static float failedSizingWidth;

/// the layer showing the current position of the mouse using a vertical line. We use a global instance as only one view at a time shows this layer
static CALayer *currentPositionMarkerLayer;
static CATextLayer *currentPositionLayer;		/// the layer showing the current position in base pairs
static NSColor *rulerLabelColor;

@implementation RulerView {
	BOOL altKeyDown;					/// Whether the option key is being pressed
	NSPoint mouseLocation;
	BOOL mouseDown;						/// tells if the user has clicked the view (and the button is still down)
	BOOL isDraggingForZoom;        		/// tells if the user is performing a zoom by dragging the mouse
	float startPoint;   				/// the location of the last mouseDown event, used to compute the area that is covered by a mouse drag
	float startSize;
	NSTimeInterval timeStamp;    		/// the timestamp of the last mouseDown event, to avoid zooming by a simple click
	__weak TraceView *traceView; 		/// the traceView associated with this view
	float *offsets;						/// allow side labels to show at the correct position in the range of a marker, considering its offset
	NSMenu *menu;						/// the view's contextual menu (allowing to zoom to the default range)
	NSTimeInterval startScrollTime;		/// The start time of a scroll action, which we use to interpret a swipe event
	float horizontalScrollAmount;
	NSButton *zoomToFitButton;
}

@synthesize applySizeStandardButton = _applySizeStandardButton;

/// Implementation notes:
/// The drawing of size labels is done in -drawRect:
/// This class doesn't use any draw method of NSRulerView because the labels must be repositioned when zooming (the magnification factor of the scrollview cannot be used on our case, see TraceScrollView.h).
/// Hence, this class use other NSRulerView methods. It only uses the fact that NSRulerView is positioned at the right place for a horizontal ruler, and that it redraws when the document view scrolls.


#pragma mark - initialization and general attributes


+ (void)initialize {
	if (self == RulerView.class) {
		
		rulerLabelColor = [NSColor colorNamed:@"rulerLabelColor"];
		
		NSImage *cursorImage = [NSImage imageNamed:@"loupeCursorBordered"];
		cursorImage.size = NSMakeSize(15, 20);
		loupeCursor = [[NSCursor alloc]initWithImage:cursorImage hotSpot:NSMakePoint(6.1, 5.9)];
		
		cursorImage = [NSImage imageNamed:@"loupeCursorMinus"];
		cursorImage.size = NSMakeSize(15, 20);
		loupeCursorMinus = [[NSCursor alloc]initWithImage:cursorImage hotSpot:NSMakePoint(6.1, 5.9)];

		NSDictionary *labelFontStyle = @{NSFontAttributeName: [NSFont labelFontOfSize:8.0], NSForegroundColorAttributeName: rulerLabelColor};
		NSDictionary *redFontStyle = @{NSFontAttributeName: [NSFont labelFontOfSize:8.0],
									   NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0 green:0.2 blue:0.2 alpha:1]};
		
		/// we populate the label array. We do it once for all rulerViews.
		NSMutableArray *temp = NSMutableArray.new;
		NSMutableArray *tempRed = NSMutableArray.new;
		for(int size = 0; size <= MAX_TRACE_LENGTH; size++) {
			NSAttributedString *rulerLabel = [[NSAttributedString alloc]initWithString:[NSString stringWithFormat:@"%d", size] attributes:labelFontStyle];
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
		currentPositionMarkerLayer.backgroundColor = NSColor.grayColor.CGColor;
		currentPositionLayer.opaque = YES;
		currentPositionMarkerLayer.anchorPoint = CGPointMake(1, 1);
		currentPositionMarkerLayer.opaque = YES;
		currentPositionMarkerLayer.bounds = CGRectMake(0, 0, 1, ruleThickness-1);
		
		currentPositionLayer = CATextLayer.new;
		currentPositionLayer.contentsScale = 3.0;	/// this makes text sharper (a non-retina display would require 2.0, so it's overkill in this situation)
		currentPositionLayer.bounds = CGRectMake(0, 0, 25, 9);					/// this ensures that the layer hides the ruler labels and tick-marks behind it (25 is larger than any string it can show)
		currentPositionLayer.anchorPoint = CGPointMake(0, 0);
		currentPositionLayer.font = (__bridge CFTypeRef _Nullable)(labelFontStyle[NSFontAttributeName]);
		currentPositionLayer.fontSize = 8.0;
		currentPositionLayer.allowsFontSubpixelQuantization = YES;
		
		[currentPositionMarkerLayer addSublayer:currentPositionLayer];
		currentPositionLayer.position = CGPointMake(1, 1.8);		/// this places this layer 1 pixel to the right of the vertical line of the currentPositionMarkerLayer
	
		
	}
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		/// we initialize the offset. There is one per size label.
		offsets = calloc(MAX_TRACE_LENGTH, sizeof(float));
		NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:frameRect
																	options: NSTrackingMouseEnteredAndExited | NSTrackingInVisibleRect | NSTrackingActiveInKeyWindow
																	  owner:self userInfo:nil];
		[self addTrackingArea:trackingArea];
//		[self addSubview:self.zoomToFitButton];
//		[[zoomToFitButton.leftAnchor constraintEqualToAnchor:self.leftAnchor constant:(30-zoomToFitButton.frame.size.width)/2+1] setActive:YES];
//		[[zoomToFitButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor] setActive:YES];

//		zoomToFitButton.hidden = YES;
	}
	return self;
}


- (NSPopUpButton *)applySizeStandardButton {
	if(!_applySizeStandardButton) {
		_applySizeStandardButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 20) pullsDown:YES];
		_applySizeStandardButton.font = [NSFont systemFontOfSize:10.0];
		_applySizeStandardButton.title = @"Apply Size Standard";
		_applySizeStandardButton.bezelStyle = NSBezelStyleRecessed;
		_applySizeStandardButton.showsBorderOnlyWhileMouseInside = YES;
		_applySizeStandardButton.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_applySizeStandardButton];
		/// we center the button horizontally and vertically in its view
		[[_applySizeStandardButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor] setActive:YES];
		[[_applySizeStandardButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor] setActive:YES];
	}
	return _applySizeStandardButton;
}


- (NSButton *)zoomToFitButton {
	if(!zoomToFitButton) {
		zoomToFitButton = [NSButton buttonWithImage:[NSImage imageNamed:@"zoomToFit"] target:self action:@selector(zoomToFit:)];
		[zoomToFitButton setFrame:NSMakeRect(0, 0, 30, ruleThickness)];
		zoomToFitButton.bezelStyle = NSBezelStyleRecessed;
		zoomToFitButton.bordered = NO;
		zoomToFitButton.showsBorderOnlyWhileMouseInside = YES;
		zoomToFitButton.imagePosition = NSImageOnly;
		zoomToFitButton.imageScaling = NSImageScaleNone;
		zoomToFitButton.translatesAutoresizingMaskIntoConstraints = NO;
		zoomToFitButton.toolTip = @"Zoom to default range";
	}
	return zoomToFitButton;
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


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if(layer == currentPositionMarkerLayer || layer == self.layer) {
		return NSNull.null;
	}
	return nil;
}


- (void)setHidden:(BOOL)hidden {
	super.hidden = hidden;
	[traceView fitVertically];
}


- (void)setClientView:(NSView *)clientView {
	super.clientView = clientView;
	traceView = (TraceView *)clientView;
	[traceView addObserver:self forKeyPath:@"trace.chromatogram.sizeStandard"
				   options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial 
				   context:sampleSizeStandardChangedContext];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == sampleSizeStandardChangedContext) {
		if(_applySizeStandardButton) {
			Chromatogram *sample = traceView.trace.chromatogram;
			_applySizeStandardButton.hidden = !sample || sample.sizeStandard != nil;
			if(!_applySizeStandardButton.hidden) {
				self.needsDisplay = YES;
				self.currentPosition = -1000;
			}
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}



#pragma mark - indicating positions


- (void)setNeedsUpdateOffsets:(BOOL)needsUpdateOffsets {
	_needsUpdateOffsets = needsUpdateOffsets;
	if(needsUpdateOffsets) {
		self.needsDisplay = YES;
	}
}


- (void)updateOffsets {
	free(offsets);
	///  there is one offset per size label. It indicates the shift in base pairs compared to the position without offset.
	offsets = calloc(MAX_TRACE_LENGTH, sizeof(float));
	for(RegionLabel *markerLabel in traceView.markerLabels) {
		float intercept = markerLabel.offset.intercept;
		float slope = markerLabel.offset.slope;
		if(slope != 1.0 || intercept != 0.0) {
			int start = (int)(markerLabel.start + 0.9);
			if(start < 0) {
				start = 0;
			}
			int end =  (int)(markerLabel.end);
			if(end > MAX_TRACE_LENGTH) {
				end = MAX_TRACE_LENGTH;
			}
			for (int i = start; i < end; i++) {
				float newI = i * slope + intercept;
				if(newI < start || newI > end) {
					offsets[i] = -1000.0;		/// this will denote that size label at index i should not be drawn, to avoid overlap
					continue;
				}
				offsets[i] = newI - (float)i;
			}
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
		/// a single layer is used for all instances, so we need to make it ours
		[self.layer addSublayer:currentPositionMarkerLayer];
		currentPositionMarkerLayer.delegate = self;
		
		/// maybe it's because the layer is moved between views, but its text sometimes becomes white and cannot be read in light mode.
		/// Setting the label's color when we acquire it appears to eliminate the issue
		self.needsChangeAppearance = YES;
	}
	currentPositionLayer.string = [NSString stringWithFormat:@"%.01f", positionToShow];
	float pos = [self xForSize:position];
	currentPositionMarkerLayer.position = CGPointMake(pos, NSMaxY(self.bounds)-1);
}


- (void)setNeedsChangeAppearance:(BOOL)needsChangeAppearance{
	/// viewDidChangeEffectiveAppearance is not adequate because this would no be called on ruler view that are in the reuse queue of a tableview. 
	_needsChangeAppearance = needsChangeAppearance;
	if(needsChangeAppearance) {
		self.needsDisplay = YES;
	}
}

/// returns the increment between consecutive size labels to show, considering the horizontal scale of the traceView
int rulerLabelIncrementForHScale(float hScale) {
	if(hScale > 50) {
		return 1;
	}
	if (hScale > 10) {
		return 5;
	}
	if (hScale > 5) {
		return 10;
	}
	if (hScale > 2) {
		return 25;
	}
	return 50;
}


- (BOOL)clipsToBounds {
	/// overrides the new default in macOS 14
	return YES;
}


- (void)drawRect:(NSRect)dirtyRect {
	if(_needsUpdateOffsets) {
		[self updateOffsets];
		self.needsUpdateOffsets = NO;
	}
	
	NSRect bounds = self.bounds;
	
	[NSColor.windowBackgroundColor setFill];
	NSRectFill(bounds);
	float topY = NSMaxY(bounds);
	
	/// We draw a thin line at the bottom of the view
	[rulerLabelColor setFill];
	NSRectFill(NSMakeRect(dirtyRect.origin.x, topY-1, dirtyRect.size.width, 1));

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

	if (isDraggingForZoom && !traceView.isMoving) {
		/// draws dragging selection as a grey rectangle (for zooming)
		[NSColor.secondaryLabelColor setFill];
		float startSizeX = [self xForSize:startSize];
		NSBezierPath *selection = [NSBezierPath bezierPathWithRect:NSMakeRect(startSizeX, topY-3, mouseLocation.x - startSizeX, topY)];
		[selection fill];
	}
	
	Chromatogram *sample = traceView.trace.chromatogram;
	
	if(sample && sample.sizingQuality == nil) {
		if(!sample.sizeStandard) {
			if(!_applySizeStandardButton) {
				[noSizing drawAtPoint: NSMakePoint(NSMidX(bounds) - noSizingWidth/2, topY-15)];
			}
		} else {
			[failedSizing drawAtPoint: NSMakePoint(NSMidX(bounds) - failedSizingWidth/2, topY-15)];
		}
		return;
	}
	
	/// we draw ruler of sizes in base pairs at the top of the view
	float hScale = traceView.hScale;
	int labelIncrement = rulerLabelIncrementForHScale(hScale);
	
	/// we determine the range of sizes in the dirty rectangle
	float startX = dirtyRect.origin.x;
	if (startX < 0) {
		startX = 0;
	}
	float startSize = [self sizeForX:startX] ;
	float endSize = startSize + dirtyRect.size.width / hScale +1;
	
	if(endSize > MAX_TRACE_LENGTH) {
		endSize = MAX_TRACE_LENGTH;
	}
	
	float previousX = traceView.leftInset - 1;
	for (int size = 0; size <= endSize; size+=labelIncrement) {
		/// we cannot start at startSize since it's a float and size must be an index, and we need to start at a given increment
		float offset= offsets[size];
		if(offset <= -1000.0) {
			continue;
		}
		float x = [self xForSize:size + offset];
		
		if(x >= previousX) { /// To avoid overlap between size labels at the edge of a marker with an offset.
			/// We draw only if the label is in the visible area of the trace view
			NSAttributedString *rulerLabel =  offset == 0? sizeArray[size] : sizeArrayRed[size];
			NSPoint origin = NSMakePoint(x- labelWidth[size]/2, topY - labelHeight[size] -2);
			
			[rulerLabel drawAtPoint:origin];
			[NSBezierPath strokeLineFromPoint:NSMakePoint(x, topY-3) toPoint:NSMakePoint(x, topY)]; /// little tick-mark
			previousX = x + labelWidth[size];
		}
	}
	
	if(self.needsChangeAppearance) {
		currentPositionLayer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
		currentPositionLayer.foregroundColor = rulerLabelColor.CGColor;
		self.needsChangeAppearance = NO;
	}
}


- (float)sizeForX:(float)x {
	return (traceView.visibleOrigin -traceView.leftInset + x) / traceView.hScale + traceView.sampleStartSize;
}


- (float)xForSize:(float)size {
	return (size - traceView.sampleStartSize) * traceView.hScale - traceView.visibleOrigin + traceView.leftInset;
}

#pragma mark - zooming-related methods


- (void)resetCursorRects {
	NSRect rect = self.bounds;
	/// We show the loupe cursor, but we avoid the top of the view if its covered by the accessory view (which should be the marker view).
	float height = self.reservedThicknessForAccessoryView;
	if(height > 0) {
		height += 0.5;
		/// This creates a separation with cursor rects of the marker view, which avoids issues where the wrong cursor may be set.
	}
	rect.size.height -= height;
	rect.origin.y += height;
	if(rect.origin.x < traceView.leftInset) {
		/// the bound origin may be negative to leave room for the vScaleView.
		rect.origin.x = traceView.leftInset;
	}
	
	NSRect visibleRect = self.visibleRect;
	NSCursor *cursor = altKeyDown? loupeCursorMinus : loupeCursor;
	[self addCursorRect:NSIntersectionRect(rect, visibleRect) cursor:cursor];
	for(NSView *view in self.subviews) {
		if(!view.hidden) {
			[self addCursorRect: NSIntersectionRect(view.frame, visibleRect) cursor:NSCursor.arrowCursor];
		}
	}
}

- (void)mouseEntered:(NSEvent *)event {
	zoomToFitButton.hidden = NO;
	/// We track if the alt key is pressed to set the loupe cursor as appropriate
	/// We don't use `keyDown:` because the view may not receive this message, yet it should be able to show the correct cursor in any situation.
	if(!eventMonitor) {
		eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged
															 handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
			
			self->altKeyDown = (event.modifierFlags & NSEventModifierFlagOption) != 0;
			[self.window invalidateCursorRectsForView:self];
			return event;
		}];
	}
	
	/// We determine whether the alt key is pressed when the mouse enters the view.
	BOOL altKeyPressed = (event.modifierFlags & NSEventModifierFlagOption) != 0;
	if(altKeyPressed != altKeyDown) {
		/// If the state of the key has changed, we reset the cursor rectangles to associate them to the correct cursor.
		/// We don't set the loupe cursor here because it doesn't appear reliable.
		altKeyDown = altKeyPressed;
		[self.window invalidateCursorRectsForView:self];
	}
}

- (void)mouseExited:(NSEvent *)event {
	if (eventMonitor) {
		[NSEvent removeMonitor:eventMonitor];
		eventMonitor = nil;
	}
	zoomToFitButton.hidden = YES;
}

- (void)mouseDown:(NSEvent *)event   {
	BOOL altKeyPressed = (event.modifierFlags & NSEventModifierFlagOption) != 0;
	if(!altKeyPressed) {
		/// The user may be starting to drag the mouse to zoom in
		mouseDown = YES;
		[loupeCursor set]; /// In case it is not already showing.
		mouseLocation= [self convertPoint:event.locationInWindow fromView:nil];
		startPoint = mouseLocation.x;
		startSize = [self sizeForX:startPoint];
		/// we record the time of the click, as we don't zoom for the first click of a double-click sequence (in case the user has dragged the mouse slightly)
		timeStamp = event.timestamp;
	} else {
		[loupeCursorMinus set];
	}
}


- (void)mouseDragged:(NSEvent *)theEvent   {
	if(mouseDown) {
		/// This check avoid `mouseDragged` beings sent after the user clicked the button to apply a size standard,
		/// (which pops a menu) and dragged the mouse on another view (which IMO is an appkit bug)
		mouseLocation = [self convertPoint:theEvent.locationInWindow fromView:nil];
		[self autoscrollWithLocation: mouseLocation];
		isDraggingForZoom = YES;
		self.needsDisplay = YES;
	}
}


- (void)autoscrollWithLocation:(NSPoint)location {
	/// if the mouse is dragged beyond our bounds (in the x dimension), we make the traceView scroll
	NSRect traceViewBounds = traceView.bounds;
	float visibleOrigin = traceView.visibleOrigin;
	float delta = location.x - [self convertPoint:NSMakePoint(visibleOrigin, 0) fromView:traceView].x;
	if(delta < 0) {	/// the mouse has passed the left limit
		if(visibleOrigin <= traceViewBounds.origin.x) {
			return;	/// this would scroll the traceView too far the right
		}
	} else {
		delta = location.x - NSMaxX(self.bounds);
		if(delta > 0) {	/// the mouse has passed the right limit
			float newOrigin = visibleOrigin + delta;
			if(newOrigin + traceView.visibleRect.size.width > NSMaxX(traceViewBounds)) {
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


- (void)mouseUp:(NSEvent *)event {
	mouseDown = NO;

	[loupeCursor set];
	if (isDraggingForZoom) {
		/// if the mouse has been dragged, we may zoom to the selected region
		if((event.timestamp - timeStamp > 0.2 && fabs(startPoint - mouseLocation.x) > 3) || fabs(startPoint - mouseLocation.x) > 10) {
			/// we do not zoom if this appears to be a simple click (of a double click sequence)
			[traceView zoomFromSize:startSize toSize:[self sizeForX:mouseLocation.x]];
		}
		self.needsDisplay = YES;  	/// even if the zoom did not occur (which tiggers a redisplay) we need to clear the selection rectangle
	} else {
		float zoomFactor = 4.0;
		BOOL altKeyPressed = (event.modifierFlags & NSEventModifierFlagOption) != 0;
		if(altKeyPressed) {
			/// The user wants to zoom out.
			[loupeCursorMinus set]; /// In case it is not already showing.
			if (event.clickCount == 2) {
				/// we zoom to the default range when the user double clicks
				[self zoomToFit:self];
				return;
			}
			zoomFactor = 0.4;
		}
		NSPoint location = [traceView convertPoint:event.locationInWindow fromView:nil];
		[traceView zoomTo:location.x withFactor:zoomFactor animate:YES];
	}
	isDraggingForZoom = NO;
}


-(void)zoomToFit:(id)sender {
	[traceView setVisibleRange:traceView.defaultRange animate:YES];
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
	if (eventMonitor) {
		[NSEvent removeMonitor:eventMonitor];
		eventMonitor = nil;
	}
	free(offsets);
	if(traceView) {
		[traceView removeObserver:self forKeyPath:@"trace.chromatogram.sizeStandard"];
	}
}

@end

