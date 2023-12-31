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
#import "DetailedViewController.h"
#import "AppDelegate.h"
#import "RulerView.h"
@class Region;


const float markerViewHeight = 20.0;

@interface MarkerView ()

/// Whether the view is in a mode that allows if the user can add a region (marker)  by clicking add dragging.
///
/// Setting this to `YES` changes the cursor to a copyDrag cursor.
/// This property will not be set to `YES` is the view returns `nil` for its ``LabelView/panel`` property.
@property (nonatomic) BOOL inAddMode;
						
/// our ruler view.
@property (nonatomic) RulerView *rulerView;

@end


@implementation MarkerView {
	CATextLayer *noPanelStringLayer;		/// a layer showing the string
	NSButton *addMarkerButton;          	/// a button that the views owns and that is used to add a new marker
	NSButton *previousMarkerButton;         /// a button that can be click to make the trace view shows the previous marker (on the left)
	NSButton *nextMarkerButton;          	/// a button that can be click to make the trace view shows the next marker (on the right)

}
@synthesize markerLabels = _markerLabels, traceView = _traceView;


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
	self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
	self.layer.opaque = YES;
	self.layer.needsDisplayOnBoundsChange = YES;			/// our layer may show a text layer indicating the absence of panel. This text must remain centered if the view resizes.
	self.layer.opaque = YES;
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
	[button.cell setBackgroundColor: NSColor.windowBackgroundColor];
	button.tag = tag;
	switch (tag) {
		case addMarkerButtonTag:
			[button.cell setButtonType:NSButtonTypeToggle];
			/// The action of this button is to tint itself according to the color of our channel.
			/// This is purely cosmetic, to signify that the added marker would be on this channel
			button.action = @selector(tintButton:);
			/// The button action is actually implemented by its binding
			[button bind:NSValueBinding toObject:self withKeyPath:@"inAddMode" options:nil];
			button.toolTip = @"Add marker (click & drag)";
			button.frame = NSMakeRect(15, 0, 15, self.bounds.size.height);
			button.autoresizingMask = NSViewMaxXMargin | NSViewHeightSizable;
			break;
		case previousMarkerButtonTag:
			button.action = @selector(moveToPreviousMarker:);
			[button bind:NSEnabledBinding toObject:self withKeyPath:@"markerLabels.@count" options:nil];
			button.frame = NSMakeRect(0, 0, 15, self.bounds.size.height);
			button.toolTip = @"Move to previous marker";
			button.autoresizingMask = NSViewMaxXMargin | NSViewHeightSizable;
			break;
		case nextMarkerButtonTag:
			button.action = @selector(moveToNextMarker:);
			[button bind:NSEnabledBinding toObject:self withKeyPath:@"markerLabels.@count" options:nil];
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
			NSColor *tintColor = self.colorsForChannels[self.channel];
			sender.contentTintColor = [tintColor blendedColorWithFraction:0.3 ofColor:NSColor.whiteColor];
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
		for(RegionLabel *label in self.traceView.binLabels) {
			/// we also update the appearance of bin labels here, because, for unclear reasons, -updateLayer is not called on the traceView
			/// despite setting needsDisplay to YES.
			[label updateForTheme];
		}
		self.needsUpdateLabelAppearance = NO;
	}
	/// We make sure the layer showing the absence of panel is centered.
	/// This could have been done with a layout constraint, but this would have required more code, probably
	if(noPanelStringLayer && !noPanelStringLayer.hidden) {
		noPanelStringLayer.position = CGPointMake(NSMidX(self.bounds), NSMidY(self.bounds));
	}
}


- (void)setBoundsOrigin:(NSPoint)newOrigin {
	/// Our bound changes to reflect changes in our traceView bounds, which avoids hiding part of the traces by the vScale view. If we don't, the marker labels don't show at the correct position.
	/// we have to reposition our navigation buttons, which should still show next to our edges.
	float delta = self.bounds.origin.x - newOrigin.x;
	[super setBoundsOrigin:newOrigin];
	for (NSView *view in self.subviews) {
		NSPoint origin = view.frame.origin;
		origin.x -= delta;
		[view setFrameOrigin:origin];
	}
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
	/// We override as the view's start and end can be masked by the buttons (we could have placed the view between the buttons, but this would have required an additional superview)
	/// We return a rectangle that corresponds to the area between the buttons. This avoid the overlap of tracking areas (that of the view, the buttons, the labels)
	float start = 0; float end = NSMaxX(self.bounds);
	if(addMarkerButton && !addMarkerButton.hidden) {
		start = NSMaxX(addMarkerButton.frame);
	}
	if(nextMarkerButton && !nextMarkerButton.hidden) {
		end = nextMarkerButton.frame.origin.x;
	}
	return NSMakeRect(start, 0, end-start, self.bounds.size.height);
}


- (NSInteger) channel {
	return self.traceView.channel;
}


- (void)setHidden:(BOOL)hidden {
	if(hidden != self.isHidden) {
		if(!self.traceView.loadedTraces && self.traceView.marker) {		/// if the view only shows a marker, it cannot hide.
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


# pragma mark - reaction to change in markers and panels


- (NSArray *)viewLabels {
	return self.markerLabels;
}


- (NSArray<ViewLabel *> *)repositionableLabels {
	return self.markerLabels;
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingPanel:(NSString *)key {
	return [NSSet setWithObject:@"traceView.panel"];
}


- (Panel *)panel {
	return self.traceView.panel;
}


- (void)updateContent {
	if(doNotCreateLabels) {
		return;
	}
	if(!self.panel) {
		self.inAddMode = NO;				/// we make sure the user won't try to add markers if there is no panel
		self.markerLabels = NSArray.new;	/// we remove marker labels and show a text indicating why the user cannot add markers
		NSString *noPanelString = @"No marker to show";
		for(Trace *trace in self.traceView.loadedTraces) {
			if(trace.chromatogram.panel && trace.chromatogram.sizingQuality) {
				/// if one sample is sized and has a panel, although the view has none, it means there are multiple panels
				noPanelString = @"Multiple panels";
				break;
			}
		}
		
		if(!noPanelStringLayer) {
			noPanelStringLayer = CATextLayer.new;
			noPanelStringLayer.font = (__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:10.0]);
			noPanelStringLayer.fontSize = 10.0;
			noPanelStringLayer.contentsScale = 2.0;		/// otherwise it looks blurry even on non-retina displays
			noPanelStringLayer.foregroundColor = NSColor.secondaryLabelColor.CGColor;
			noPanelStringLayer.actions = @{@"hidden": [NSNull null], @"position": [NSNull null]};
			noPanelStringLayer.alignmentMode = kCAAlignmentCenter;
			noPanelStringLayer.bounds = CGRectMake(0, 0, 100, 15);
			[self.layer addSublayer:noPanelStringLayer];
		}
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
															
		NSMutableArray *temp = NSMutableArray.new;
		for (Mmarker *marker in [self.panel markersForChannel:self.channel]) {
			RegionLabel *label = [RegionLabel regionLabelWithRegion:marker view:(TraceView *)self];
			if(!self.traceView.loadedTraces) {
				/// if the traceView shows no trace, it means it only shows a marker.
				/// We only enable the label for that marker
				label.enabled = marker == self.traceView.marker;
			}
			[temp addObject:label];
		}
		self.markerLabels = [NSArray arrayWithArray:temp];
	}
}


-(void)setMarkerLabels:(NSArray<RegionLabel *> * _Nonnull)markerLabels {
	for(RegionLabel *label in _markerLabels) {
		if([markerLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_markerLabels = markerLabels;
	if(self.markerLabels.count > 0) {
		self.needsUpdateLabelAppearance = YES;
		self.needsLayoutLabels = YES;
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
	if(self.traceView.isMoving) {
		return;
	}
	[super updateTrackingAreas];
	[self updateTrackingAreasOf:self.markerLabels];
}


- (void)updateCursor {
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


- (void)mouseEntered:(NSEvent *)event {
	[super mouseEntered:event];
	[self updateCursor];
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
	NSArray *sortedMarkerLabels = [self.markerLabels sortedArrayUsingKey:@"start" ascending:YES];
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
	NSArray *sortedMarkerLabels = [self.markerLabels sortedArrayUsingKey:@"start" ascending:YES];
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
		/// This is basically the same method as used by the traceView to add a bin
		Panel *panel = self.panel;
		if(!panel.managedObjectContext) {
			return;
		}
		
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
		
		float start = (position < clickedPosition) ? position:clickedPosition;
		float end = (position < clickedPosition) ? clickedPosition:position;
		
		/// we add a new marker in a child context of the view context, as the marker is not in its final state until mouseUp, and changes should not be undoable
		
		if(panel.objectID.isTemporaryID) {
			 [panel.managedObjectContext obtainPermanentIDsForObjects:@[panel] error:nil];
		}
		temporaryContext =[[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
		temporaryContext.parentContext = panel.managedObjectContext;
		/// we materialize the panel in this context, as the new marker must be added to it
		panel = [temporaryContext existingObjectWithID:panel.objectID error:nil];

		if(panel.managedObjectContext != temporaryContext) {
			NSError *error = [NSError errorWithDescription:@"The marker could not be added because an error occurred in the database." suggestion:@"You may quit the application and try again."];
			[[NSAlert alertWithError:error] beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
			}];
			return;
		}
		
		Mmarker *newRegion = [[Mmarker alloc] initWithStart:start end:end channel:self.channel panel:panel];
		if(!newRegion) {
			return;
		}
		/// we give a blank name. Only on mouseUp the marker will get its final name (we use a space as an empty name causes issues)
		newRegion.name = @" ";
		RegionLabel *label = [RegionLabel regionLabelWithRegion:newRegion view:(TraceView *)self];
		self.markerLabels = [self.markerLabels arrayByAddingObject:label];
		
		/// we highlight the label and the correct edge to allow immediate sizing (see below)
		label.highlighted = YES;
		label.clicked = YES;
		label.clickedEdge = position < clickedPosition? leftEdge: rightEdge;
		[NSCursor.resizeLeftRightCursor set];

		self.inAddMode = NO;

		return;
	}
	
	if(!draggedLabel) {
		draggedLabel = self.activeLabel;
	}
	
	if(draggedLabel && ((RegionLabel *)draggedLabel).clickedEdge != noEdge) {
		[draggedLabel drag];
		[self autoscrollWithDraggedLabel:draggedLabel];
		self.rulerView.currentPosition  = [self sizeForX:self.mouseLocation.x];
	}
}




- (void)autoscrollWithDraggedLabel:(ViewLabel *)draggedLabel {
	/// we autoscroll if the mouse is dragged over the rightmost button on the left (the "+"' button), or the button on the right
	if(!NSPointInRect(self.mouseLocation, draggedLabel.frame)) {
		return;
	}
	TraceView *traceView = self.traceView;
	NSRect traceViewBounds = traceView.bounds;
	float location = self.mouseLocation.x;
	NSRect rect = self.visibleRect;
	float leftLimit = rect.origin.x;
	float rightLimit = NSMaxX(rect);

	/// we scroll the trace view if the mouse goes beyond the limits
	float delta = location - leftLimit;
	if(delta < 0) {	/// the mouse has passed the left limit
		if(traceView.visibleOrigin <= traceViewBounds.origin.x) {
			return;	/// this would scroll the traceView too far
		}
	} else {
		delta = location - rightLimit;
		if(delta > 0) {	/// the mouse has passed the right limit
			float newOrigin = traceView.visibleOrigin + delta;
			if(newOrigin + traceView.visibleRect.size.width > NSMaxX(traceViewBounds)) {
				return;
			}
		} else {
			return;	/// here, the mouse is within the limits, we don't need to scroll
		}
	}
	
	BaseRange newRange = self.traceView.visibleRange;
	newRange.start += delta/self.traceView.hScale;
	self.traceView.visibleRange = newRange;
	
}


- (BOOL)resignFirstResponder {
	self.rulerView.currentPosition = -10000;
	if(self.inAddMode) {
		/// this check is important, as executing the instruction below changes the button state, which enables it
		/// (which we don't want if there is no panel)
		self.inAddMode = NO;  /// when we are no longer the first responder, the user will no longer be able to add a marker. They will have to click the button again
	}
	
	RegionLabel *activeLabel = self.activeLabel;
	if(!activeLabel.attachedPopover) {
		self.activeLabel.highlighted = NO;
	}
	return YES;
}


@end
