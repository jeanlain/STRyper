//
//  MarkerView.m
//  STRyper
//
//  Created by Jean Peccoud on 05/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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



#import "MarkerView.h"
#import "Trace.h"
#import "Mmarker.h"
#import "RulerView.h"
@class Region;


const float markerViewHeight = 20.0;

@interface MarkerView () {
	NSArray <RegionLabel *> *sortedMarkerLabels; /// marker labels sorted by increasing start size
}

/// Whether the view is in a mode that allows if the user can add a region (marker)  by clicking add dragging.
///
/// Setting this to `YES` changes the cursor to a copyDrag cursor.
/// This property will not be set to `YES` if the view returns `nil` for its ``LabelView/panel`` property.
@property (nonatomic) BOOL inAddMode;
						
/// our ruler view.
@property (nonatomic) RulerView *rulerView;

@end


@implementation MarkerView {
	CATextLayer *noPanelStringLayer;		/// a layer showing the string shown when no marker can be shown nor added
	NSButton *addMarkerButton;          	/// a button that the views owns and that is used to add a new marker
	NSButton *previousMarkerButton;         /// a button that can be click to make the trace view shows the previous marker (on the left)
	NSButton *nextMarkerButton;          	/// a button that can be click to make the trace view shows the next marker (on the right)

}
@synthesize markerLabels = _markerLabels, traceView = _traceView, backgroundLayer = _backgroundLayer;


/// The tag used to identify the button that are our subviews
/// these tags are set in IB
enum ButtonTag : NSUInteger {
	addMarkerButtonTag	= 0,
	previousMarkerButtonTag = 1,
	nextMarkerButtonTag = 2
} ButtonTag;


# pragma mark - general attribute setting


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		[self setAttributes];
	}
	return self;
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		[self setAttributes];
	}
	return self;
}


-(void)setAttributes {
	self.layer.opaque = YES;
	self.layer.needsDisplayOnBoundsChange = YES;			/// our layer may show a text layer indicating the absence of panel. This text must remain centered if the view resizes.
	previousMarkerButton = [self defaultButtonWithImageName:@"goLeft" tag:previousMarkerButtonTag];
	addMarkerButton = [self defaultButtonWithImageName:@"addCircle" tag:addMarkerButtonTag];
	nextMarkerButton = [self defaultButtonWithImageName:@"goRight" tag:nextMarkerButtonTag];

}


- (BOOL)isOpaque {
	return YES;
}


- (BOOL)clipsToBounds {
	return YES;
}


- (RulerView *)rulerView {
	if(!_rulerView && [self.superview isKindOfClass:RulerView.class]) {
		_rulerView = (RulerView *)self.superview;
	}
	return _rulerView;
}


- (TraceView *)traceView {
	if(!_traceView) {
		NSScrollView *scrollView = (NSScrollView *)self.superview.superview;
		if([scrollView respondsToSelector:@selector(documentView)]) {
			TraceView *traceView = scrollView.documentView;
			if([traceView isKindOfClass:TraceView.class]) {
				_traceView = traceView;
			}
		}
	}
	return _traceView;
}


- (Trace *)trace {
	return self.traceView.trace;
}


-(NSArray *)loadedTraces {
	return self.traceView.loadedTraces;
}


/// Used to return a button we use to add a marker or to navigate between markers
-(NSButton *)defaultButtonWithImageName:(NSString *)imageName tag:(int) tag {
	NSButton *button = [NSButton buttonWithImage:[NSImage imageNamed:imageName] target:self action:nil];
	button.bezelStyle = NSBezelStyleRecessed;
	button.bordered = NO;
	button.showsBorderOnlyWhileMouseInside = YES;
	button.imagePosition = NSImageOnly;
	button.imageScaling = NSImageScaleNone;
	button.tag = tag;
	switch (tag) {
		case addMarkerButtonTag:
			[button.cell setButtonType:NSButtonTypeToggle];
			/// The action of this button is to tint itself according to the color of our channel.
			/// This is purely cosmetic, to signify that the added marker would be on this channel
			button.action = @selector(tintButton:);
			/// The button action is actually implemented by its binding
			[button bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(inAddMode)) options:nil];
			button.toolTip = @"Add marker (click & drag)";
			button.frame = NSMakeRect(15, 0, 15, self.bounds.size.height);
			button.autoresizingMask =  NSViewHeightSizable;
			break;
		case previousMarkerButtonTag:
			button.action = @selector(moveToPreviousMarker:);
			button.frame = NSMakeRect(0, 0, 15, self.bounds.size.height);
			button.toolTip = @"Move to previous marker";
			button.autoresizingMask = NSViewHeightSizable;
			break;
		case nextMarkerButtonTag:
			button.action = @selector(moveToNextMarker:);
			button.frame = NSMakeRect(NSMaxX(self.bounds) - 15, 0, 15, self.bounds.size.height);
			button.toolTip = @"Move to next marker";
			button.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
		default:
			break;
	}
	[self addSubview:button];
	return button;
}

/// Tints the sender button according to the color of our channel.
-(IBAction)tintButton:(NSButton *)sender {
	if(!sender.isBordered && sender.image.isTemplate) {
		if (@available(macOS 10.14, *)) {
			ChannelNumber channel = self.channel;
			NSArray *colorsForChannels = self.class.colorsForChannels;
			if(colorsForChannels.count > channel && channel >= 0) {
				NSColor *tintColor = colorsForChannels[channel];
				sender.contentTintColor = [tintColor blendedColorWithFraction:0.3 ofColor:NSColor.whiteColor];
			}
		}
	}
}



- (void)updateLayer {
	if(self.needsUpdateLabelAppearance) {
		self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
		if(noPanelStringLayer) {
			noPanelStringLayer.foregroundColor = NSColor.secondaryLabelColor.CGColor;
		}
		for(RegionLabel *label in self.markerLabels) {
			[label updateForTheme];
		}
		self.needsUpdateLabelAppearance = NO;
	}
	/// We make sure the layer showing the absence of panel is centered.
	/// This could have been done with a layout constraint, but this would have required more code, probably
	if(noPanelStringLayer && !noPanelStringLayer.hidden) {
		noPanelStringLayer.position = CGPointMake(NSMidX(self.bounds), NSMidY(self.bounds));
	} else {
		[super updateLayer];
	}
}

- (CALayer *)backgroundLayer {
	if(!_backgroundLayer) {
		_backgroundLayer = CALayer.new;
		_backgroundLayer.delegate = self;
		_backgroundLayer.anchorPoint = CGPointMake(0, 0);
		
		/// The layer only occupies the area between navigation buttons, such that marker labels don't overlap with the buttons
		/// We could have used a CAScrollLayer as the view looks like it scrolls, but since the marker labels need to be repositioned at every scroll step
		/// to make the marker names visible, this wouldn't help much.
		_backgroundLayer.masksToBounds = YES;
		NSRect visibleRect = self.visibleRect;
		_backgroundLayer.bounds = visibleRect;
		_backgroundLayer.position = visibleRect.origin;
		[self.layer addSublayer:_backgroundLayer];
	}
	return _backgroundLayer;
}

# pragma mark - geometry

- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if(layer == _backgroundLayer || layer == self.layer) {
		return NSNull.null;
	}
	return nil;
}

- (void)setBoundsOrigin:(NSPoint)newOrigin {
	/// Our bound changes to reflect changes in our traceView bounds, which avoids hiding part of the traces by the vScale view. 
	/// If we don't, the marker labels don't show at the correct position.
	/// we have to reposition our navigation buttons, which should still show next to our edges.
	float delta = self.bounds.origin.x - newOrigin.x;
	[super setBoundsOrigin:newOrigin];
	for (NSView *view in self.subviews) {
		NSPoint origin = view.frame.origin;
		origin.x -= delta;
		[view setFrameOrigin:origin];
	}
}


- (void)setFrameSize:(NSSize)newSize {
	[super setFrameSize:newSize];
	NSRect visibleRect = self.visibleRect;
	self.backgroundLayer.bounds = visibleRect;
	self.backgroundLayer.position = visibleRect.origin;
}


- (float)visibleOrigin {
	return self.traceView.visibleOrigin;
}


-(float)hScale {
	return self.traceView.hScale;
}


- (float)sampleStartSize {
	return self.traceView.sampleStartSize;
}


- (float)sizeForX:(float)xPosition {
	return [self.rulerView sizeForX:xPosition];
}


- (float)xForSize:(float)size {
	return [self.rulerView xForSize:size];
}


- (NSRect)visibleRect {
	/// We return a rectangle that corresponds to the area between the buttons. This avoid the overlap between marker labels and buttons
	float start = 0; float end = NSMaxX(self.bounds);
	if(addMarkerButton && !addMarkerButton.hidden) {
		start = NSMaxX(addMarkerButton.frame);
	}
	if(nextMarkerButton && !nextMarkerButton.hidden) {
		end = nextMarkerButton.frame.origin.x;
	}
	return NSMakeRect(start, 0, end-start, self.bounds.size.height);
}


- (ChannelNumber) channel {
	return self.traceView.channel;
}


- (void)setHidden:(BOOL)hidden {
	if(hidden != (self.rulerView.reservedThicknessForAccessoryView == 0)) {
		if(!self.traceView.loadedTraces && self.traceView.marker) {		
			/// if the view only shows a marker, it cannot hide.
			hidden = NO;
		}
		super.hidden = hidden;
		if(hidden) {
			for(RegionLabel *label in self.markerLabels) {
				label.region.editState = editStateNil;		/// TO CHECK if this is still relevant
			}
		}
		/// when hidden, we also get a thickness of zero to avoid showing a blank space above the ruler
		self.rulerView.reservedThicknessForAccessoryView = hidden? 0: markerViewHeight;
		[self.traceView fitVertically];
	}
}

- (BOOL)isMoving {
	return self.traceView.isMoving;
}

- (BOOL)resizedWithAnimation {
	return self.traceView.resizedWithAnimation;
}

# pragma mark - reaction to change in markers and panels


- (NSArray *)viewLabels {
	return self.markerLabels;
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingPanel:(NSString *)key {
	return [NSSet setWithObject:@"traceView.panel"];
}


- (Panel *)panel {
	return self.traceView.panel;
}


- (void)updateContent {

	TraceView *traceView = self.traceView;
	if(!self.panel) {
		self.inAddMode = NO;				/// we make sure the user won't try to add markers if there is no panel
		self.markerLabels = NSArray.new;	/// we remove marker labels and show a text indicating why the user cannot add markers
		NSString *noPanelString;
		if(traceView.channel == noChannelNumber) {
			/// We use the marker view to help the user understand why the trace view does not show a trace
			noPanelString = @"No fluorescence data for this channel";
		} else {
			for(Trace *trace in traceView.loadedTraces) {
				if(trace.chromatogram.panel && trace.chromatogram.sizingQuality) {
					/// if one sample is sized and has a panel, although the view has none, it means there are multiple panels
					noPanelString = @"Multiple panels";
					break;
				}
			}
		}
		if(!noPanelString) {
			noPanelString = @"No panel to show";
		}
		
		if(!noPanelStringLayer) {
			noPanelStringLayer = CATextLayer.new;
			noPanelStringLayer.font = (__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:10.0]);
			noPanelStringLayer.fontSize = 10.0;
			noPanelStringLayer.contentsScale = 3.0;
			noPanelStringLayer.actions = @{@"hidden": [NSNull null], @"position": [NSNull null]};
			noPanelStringLayer.alignmentMode = kCAAlignmentCenter;
			noPanelStringLayer.bounds = CGRectMake(0, 0, 200, 15);
			[self.layer addSublayer:noPanelStringLayer];
		}
		noPanelStringLayer.foregroundColor = traceView.channel == noChannelNumber? NSColor.orangeColor.CGColor : NSColor.secondaryLabelColor.CGColor;
		noPanelStringLayer.string = noPanelString;
		noPanelStringLayer.hidden = NO;
		addMarkerButton.enabled = NO;
		self.needsDisplay = YES;
		
	} else {
		if(noPanelStringLayer) {
			noPanelStringLayer.hidden = YES;
		}
				
		/// we cannot be used to add a marker if the traceView doesn't show a trace (hence only a marker)
		/// it doesn't make sense to add a marker when the view is focused on an existing marker
		addMarkerButton.enabled = self.trace != nil;
		
		NSArray *markers = [self.panel markersForChannel:self.channel];
		if(markers.count == 0) {
			self.markerLabels = NSArray.new;
			return;
		}
		
		self.needsRepositionLabels = YES;
		/*
		extern uint64_t dispatch_benchmark(size_t count, void (^block)(void));
		uint64_t t = dispatch_benchmark(10, ^{
			@autoreleasepool {
				[self reuseRegionLabels:self.markerLabels givenRegions:markers];
			}
		});
		
		NSLog(@"Reuse Avg. Runtime: %llu ns", t);
		
		t = dispatch_benchmark(10, ^{
			@autoreleasepool {
				[self reuseRegionLabels:nil givenRegions:markers];
			}
		});
		
		NSLog(@"No Reuse Avg. Runtime: %llu ns", t); */
	
		NSArray *markerLabels = [self regionLabelsForRegions:markers reuseLabels:self.markerLabels];
		Mmarker *marker = traceView.marker;
		BOOL showMarkerOnly = marker && !traceView.trace;
		for(RegionLabel *label in markerLabels) {
			label.enabled = label.region == marker || !showMarkerOnly;
		}
		self.markerLabels = markerLabels;
	}
}



-(void)setMarkerLabels:(NSArray<RegionLabel *> * _Nonnull)markerLabels {
	for(RegionLabel *label in _markerLabels) {
		if([markerLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_markerLabels = markerLabels;
	NSInteger markerCount = markerLabels.count;
	
	sortedMarkerLabels = markerCount > 1? [markerLabels sortedArrayUsingKey:@"start" ascending:YES] : markerLabels;
	if(markerCount > 0) {
		self.needsUpdateLabelAppearance = YES;
		self.needsRepositionLabels = YES;
	}
	if(self.hScale > 0) {
		[self updateNavigationButtonEnabledState];
	}
}


- (void)labelDidChangeEditState:(RegionLabel *)label {
	if(label.editState != editStateNil) {
		/// if a marker label enters some edit state, exits the add mode
		self.inAddMode = NO;
	}
}


- (BaseRange)safeRangeForBaseRange:(BaseRange)range {
	BaseRange safeRange = range;
	NSRect rect = NSInsetRect(self.visibleRect, 4, 0);
	float leftDiff = rect.origin.x - self.traceView.leftInset;
	if(leftDiff < 0) {
		rect.origin.x -= leftDiff;
		rect.size.width += leftDiff;
		leftDiff = 0;
	}
	float rightDiff = NSMaxX(self.bounds) - NSMaxX(rect);
	float targetHScale = rect.size.width / range.len;
	leftDiff = leftDiff/targetHScale;
	safeRange.start -= leftDiff;
	safeRange.len += leftDiff + rightDiff/targetHScale;
	return safeRange;
}

# pragma mark - reaction to user actions

- (void)updateTrackingAreas {
	if(!self.traceView.isMoving) {
		[super updateTrackingAreas];
		[self updateTrackingAreasOf:self.markerLabels];
	}
}


- (void)updateCursor {
	if(!self.traceView.isMoving && NSEvent.pressedMouseButtons == 0) {
		if(hoveredMarkerLabel.hoveredEdge) {
			[NSCursor.resizeLeftRightCursor set];
		} else if(hoveredMarkerLabel) {
			[NSCursor.arrowCursor set];
		} else if(self.inAddMode && mouseIn) {
			[NSCursor.dragCopyCursor set];
		} else {
			[NSCursor.arrowCursor set];
		}
	}
}



- (void)resetCursorRects {
	/// we make sure that the buttons we have as subviews show the arrow cursor
	for(NSButton *button in self.subviews) {
		/// the cursor rect leaves 2 points at the top of bottom of the button, so that it is not as tall as the view.
		/// Otherwise the cursor may not change when entering the rect (Ventura+ does not have this issue).
		[self addCursorRect:  NSInsetRect(button.frame, 0, 2) cursor:NSCursor.arrowCursor];
	}
}


-(RegionLabel *)moveToPreviousMarker:(id)sender {
	if(self.markerLabels.count == 0) {
		return nil;
	}
	BaseRange visibleRange = self.traceView.visibleRange;
	float rangeStart = visibleRange.start;
	RegionLabel *targetLabel;
	for(RegionLabel *markerLabel in sortedMarkerLabels) {
		if(markerLabel.startSize < rangeStart) {
			targetLabel = markerLabel;
		} else if(markerLabel.startSize > rangeStart) {
			break;
		}
	}
	if(targetLabel == nil) {
		RegionLabel *firstLabel = sortedMarkerLabels.firstObject;
		if(sender == previousMarkerButton || firstLabel.endSize <= visibleRange.start + visibleRange.len) {
			targetLabel = firstLabel;
		}
	}
	if(targetLabel) {
		[self.traceView zoomToMarkerLabel:targetLabel];
		return  targetLabel;
	}
	return nil;
}


-(RegionLabel *)moveToNextMarker:(id)sender {
	if(self.markerLabels.count == 0) {
		return nil;
	}
	BaseRange visibleRange = self.traceView.visibleRange;
	float rangeEnd = visibleRange.start + visibleRange.len;
	RegionLabel *targetLabel;
	for(RegionLabel *markerLabel in sortedMarkerLabels) {
		if(markerLabel.endSize > rangeEnd) {
			targetLabel = markerLabel;
			break;
		}
	}
	if(targetLabel == nil) {
		RegionLabel *lastLabel = sortedMarkerLabels.lastObject;
		if(sender == nextMarkerButton || lastLabel.startSize >= visibleRange.start) {
			targetLabel = lastLabel;
		}
	}
	if(targetLabel) {
		[self.traceView zoomToMarkerLabel:targetLabel];
		return targetLabel;
	}
	return nil;
}


- (void)updateNavigationButtonEnabledState {
	if(sortedMarkerLabels.count > 0) {
		NSRect visibleRect = self.visibleRect;
		float rightSize = [self sizeForX:NSMaxX(visibleRect)];
		float leftSize = [self sizeForX:visibleRect.origin.x];
		previousMarkerButton.enabled = leftSize > sortedMarkerLabels.firstObject.startSize;
		nextMarkerButton.enabled = rightSize < sortedMarkerLabels.lastObject.endSize;
	} else {
		previousMarkerButton.enabled = NO;
		nextMarkerButton.enabled = NO;
	}
}


- (void)setInAddMode:(BOOL)inAddMode {
	if(inAddMode && (!self.panel || self.trace == nil)) {
		/// we make sure not to enter the add mode if there is no panel or trace to show
		return;
	}
	_inAddMode = inAddMode;
	if(inAddMode) {
		[self.window makeFirstResponder:self];
		/// When the user wants to add a marker, we makes sure all markers exit their edit state.
		for(RegionLabel *label in self.markerLabels) {
			label.region.editState = editStateNil;
		}
	}
	/// when the user can add a marker, we show it with a special cursor
	[self updateCursor];
}


- (void)cancelOperation:(id)sender {
	self.inAddMode = NO;			/// the cancel key exits the add mode.
	[self.traceView cancelOperation:sender];
}


- (void)mouseMoved:(NSEvent *)event {
	if(!mouseIn) {
		return;
	}
	self.mouseLocation = [self convertPoint:event.locationInWindow fromView:nil];
}


- (void)mouseExited:(NSEvent *)event {
	[super mouseExited:event];
	self.rulerView.currentPosition = -10000;		/// this removes the display of the current cursor position from the ruler view
}


- (void)setMouseLocation:(NSPoint)location {
	_mouseLocation = location;	
}


- (void)mouseDragged:(NSEvent *)event {
	/// when the user drags the mouse, they may be adding or resizing a marker
	NSPoint point =  [self convertPoint:event.locationInWindow fromView:nil];
	self.mouseLocation = point;

	if(self.inAddMode & !hoveredMarkerLabel && mouseIn) {
		/// The user adds a new marker by dragging in an empty area (no label is clicked).
		float position = [self sizeForX:self.mouseLocation.x];         	/// we convert the mouse position in base pairs
		float clickedPosition =  [self sizeForX:self.clickedPoint.x];   /// we obtain the original clicked position in base pairs
		
		if(fabs(point.x - self.clickedPoint.x) < 4) {
			/// we do not yet react when the drag is to short, to avoid creating a marker that is too short
			return;
		}
		
		/// we check if we have room to add the new marker
		float safePosition = position < clickedPosition? clickedPosition - 3.0 : clickedPosition + 3.0;
		for(Mmarker *marker in [self.panel markersForChannel:self.channel]) {
			if(safePosition >= marker.start && safePosition <= marker.end) {
				return;
			}
		}
		
		NSError *error;
		draggedLabel = [RegionLabel regionLabelWithNewRegionByDraggingInView:self error:&error];
		if(error) {
			error = [NSError errorWithDescription:@"The marker could not be added because an error occurred in the database."
												suggestion:@"You may quit the application and try again"];
			[[NSAlert alertWithError:error] beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
			}];
		} else if(draggedLabel) {
			self.markerLabels = [self.markerLabels arrayByAddingObject:(RegionLabel *)draggedLabel];
			self.inAddMode = NO;
			[NSCursor.resizeLeftRightCursor set];
		}
	
		return;
	}
	
	if(!draggedLabel) {
		[self.activeLabel mouseDraggedInView];
	} else {
		[draggedLabel mouseDraggedInView];
		self.rulerView.currentPosition  = [self sizeForX:point.x];
	}
}


- (void)labelIsDragged:(ViewLabel *)label {
	draggedLabel = label;
	[self autoscrollWithDraggedLabel:(RegionLabel *)label];
}



- (void)autoscrollWithDraggedLabel:(RegionLabel*)draggedLabel {
	/// we autoscroll if the mouse is dragged over the rightmost button on the left (the "+"' button), or the button on the right
	NSRect labelFrame = draggedLabel.frame;
	
	TraceView *traceView = self.traceView;
	NSRect traceViewBounds = traceView.bounds;
	float location = draggedLabel.clickedEdge == leftEdge? NSMinX(labelFrame) : NSMaxX(labelFrame);
	NSRect visibleRect = self.visibleRect;
	float leftLimit = visibleRect.origin.x;
	float rightLimit = NSMaxX(visibleRect);

	/// we scroll the trace view if the label frame goes beyond the limits
	float delta = location - leftLimit;
	float newOrigin = traceView.visibleOrigin;
	if(delta < 0) {	/// the mouse has passed the left limit
		newOrigin += delta;
		if(newOrigin <= traceViewBounds.origin.x) {
			return;	/// this would scroll the traceView too far
		}
	} else {
		delta = location - rightLimit;
		if(delta > 0) {	/// the mouse has passed the right limit
			newOrigin += delta;
			if(newOrigin + traceView.visibleRect.size.width > NSMaxX(traceViewBounds)) {
				return;
			}
		} else {
			return;	/// here, the mouse is within the limits, we don't need to scroll
		}
	}
	
	[traceView scrollPoint:NSMakePoint(newOrigin, 0)];
	
}


- (BOOL)resignFirstResponder {
	self.rulerView.currentPosition = -10000;
	if(self.inAddMode) {
		/// this check is important, as executing the instruction below changes the button state, which enables it (a cocoa binding bug, IMO)
		/// (which we don't want if there is no panel)
		self.inAddMode = NO;  /// when we are no longer the first responder, the user will no longer be able to add a marker. They will have to click the button again
	}
	
	RegionLabel *activeLabel = self.activeLabel;
	if(!activeLabel.attachedPopover) {
		activeLabel.highlighted = NO;
	}
	return YES;
}


@end
