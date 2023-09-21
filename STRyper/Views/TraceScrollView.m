//
//  TraceScrollView.m
//  STRyper
//
//  Created by Jean Peccoud on 14/12/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
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



#import "TraceScrollView.h"
#import "TraceView.h"
#import "VScaleView.h"
#import "MarkerView.h"

@implementation TraceScrollView

{
	VScaleView *vScaleView;   		/// the vertical scale view is created by us and added as a subview
	__weak TraceView *traceView;	/// A shortcut to the document view (if a traceView)
	
	/// The layer that draws our background.
	/// The default background property does not work well with animations (the background rectangle and its color are not animated).
	CALayer *backgroundLayer;
	
	RegionLabel *targetLabel;		/// the label of the marker to which we move to after a swipe gesture
	float previousDeltaX;			/// The scrollingDeltaX of the last scrollWheel event, used to determine if we should move to the next/previous marker.
}



extern const float vScaleViewWidth;
const NSBindingName AllowSwipeBetweenMarkersBinding = @"allowSwipeBetweenMarkers";


# pragma mark - general attribute setting


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		[self setAttributes];
	}
	return self;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		[self setAttributes];
	}
	return self;
}


-(void)setAttributes {
	self.drawsBackground = NO;	/// must be set so, otherwise the view doesn't react to the changes in the backgroundLayer's color
								/// also, this improves the tiling of the subviews during animation
	self.hasHorizontalScroller = YES;
	self.verticalScrollElasticity = NSScrollElasticityNone;
	self.scrollerStyle = NSScrollerStyleLegacy;
	self.usesPredominantAxisScrolling = NO;
	self.borderType = NSNoBorder;
	self.rulersVisible = YES;
	
	self.wantsLayer = YES;
	backgroundLayer = CALayer.new;
	backgroundLayer.opaque = YES;
	[self.layer addSublayer:backgroundLayer];
	self.backgroundColor = NSColor.whiteColor;

   self.automaticallyAdjustsContentInsets = NO;
	self.contentInsets =  NSEdgeInsetsZero;
}


- (void)setDocumentView:(__kindof NSView *)documentView {
	[super setDocumentView:documentView];
	if([self.documentView isKindOfClass:TraceView.class]) {
		traceView = self.documentView;
		vScaleView = [[VScaleView alloc] initWithFrame:NSMakeRect(0, 0, vScaleViewWidth, NSMaxY(self.bounds)-20) ]; /// the frame isn't very important as it is set during -tile
		traceView.vScaleView = vScaleView;
		vScaleView.wantsLayer = YES;
		[self addSubview:vScaleView];
	}
}


- (void)setScrollerStyle:(NSScrollerStyle)scrollerStyle {
	/// We enforce the legacy scroller style (if we didn't and if the user connects a magic mouse or trackpad after the app launch, the legacy scroller style could change)
	if(scrollerStyle == NSScrollerStyleLegacy) {
		[super setScrollerStyle:scrollerStyle];
	}
}


- (void)setBackgroundColor:(NSColor *)backgroundColor {
	backgroundLayer.backgroundColor = backgroundColor.CGColor;
}


- (NSColor *)backgroundColor {
	if(backgroundLayer.backgroundColor) {
		return [[NSColor colorWithCGColor: backgroundLayer.backgroundColor] copy];
	}
	else return NSColor.clearColor;
}


- (BOOL)isOpaque {
	return YES;		/// we assume that the background layer will not be hidden or given some non-opaque color.
}
 

- (NSInteger)tag {
	return 10;
}




# pragma mark - tiling


- (void)tile {
	[super tile];
	/// we adjust the background layer to the contentView's frame
	/// We didn't use layout constrains, because they don't  adapt well to animation
	if(!NSEqualRects(self.contentView.frame, backgroundLayer.frame)) {
		[CATransaction begin];
		CATransaction.disableActions = !NSAnimationContext.currentContext.allowsImplicitAnimation;
		CGRect frame = self.contentView.frame;
		backgroundLayer.frame = frame;
		[CATransaction commit];
	}
	
	/// we adjust the position of the vScaleView
	if(!vScaleView) {
		return;
	}
	float scrollerHeight = self.horizontalScroller.frame.size.height;

	float topInset = 0;
	if(self.hasHorizontalRuler && !self.horizontalRulerView.hidden) {
		topInset = self.horizontalRulerView.frame.size.height -3 ;		/// the vscaleView slightly overlaps the ruler view to avoid clipping the topmost fluorescence level displayed.
	}
	NSRect newFrame = NSMakeRect(0, topInset, vScaleViewWidth, self.frame.size.height - scrollerHeight - topInset);
	
	if(!NSEqualRects(vScaleView.frame, newFrame)) {
		vScaleView.frame = newFrame;
	}
}

# pragma mark - user interactions

/// NOTE:  We don't use NSScrollView magnification methods as they would magnify the content in both dimensions and magnify everything, including curve thickness, labels, etc.


- (void)scrollClipView:(NSClipView *)aClipView toPoint:(NSPoint)aPoint {
	NSScrollerPart hitPart = self.horizontalScroller.hitPart;
	float hScale = traceView.hScale;
	
	if(hScale <= 0 || traceView.isResizing || targetLabel || !(previousDeltaX != 0 || hitPart != NSScrollerNoPart)) {
		/// the view being resized tends to trigger this method which messes with the scrolling. So we don't scroll in this situation.
		/// We also check the presence of a scroll event, because appkits tends to call this method inappropriately, in particular after a swipe between markers.
		/// The swipe requires ignoring some scrollWheel messages that occur after the fingers have left the trackpad (inertial scrolling events after the swipe).
		/// Appkit apparently buffers these events and sees fit to call this method when the mouse exists us,
		/// to make us scroll the document view where it should have scrolled if we did not ignore the scrollWheel messages
		/// This causes a jump in scroll position.
		return;
	}
	
	BaseRange newRange = traceView.visibleRange;
	newRange.start = aPoint.x / hScale + traceView.sampleStartSize;
	
	if(hitPart == NSScrollerIncrementPage || hitPart == NSScrollerDecrementPage) {
		/// if the user is scrolling "by page", we move the view to the newRange with animation
		/// this makes other trace views move in sync (otherwise, only the focus view would move with animation, the others would jump)
		/// and they change their vertical scale during the scroll (not after) if they autoscale to the highest visible peak
		[traceView setVisibleRange:newRange animate:YES];
	} else {
		/// else we just set the visible range.
		traceView.visibleRange = newRange;
	} 
}


- (void)scrollWheel:(NSEvent *)theEvent {

	float deltaX = theEvent.scrollingDeltaX;
	BOOL vertical = fabs(deltaX) < fabs(theEvent.scrollingDeltaY);
	BOOL altKeyDown = (theEvent.modifierFlags & NSEventModifierFlagOption) != 0;
	if (altKeyDown) {
		if(vertical) {
			/// if scrolling is mostly vertical and the alt key is pressed, we zoom the trace
			NSPoint mouseLocation = [self.documentView convertPoint:theEvent.locationInWindow fromView:nil];
			float zoomPoint = mouseLocation.x;
			float zoomFactor = (40 + theEvent.scrollingDeltaY)/40;
			mouseLocation.x = zoomPoint*zoomFactor;
			[traceView zoomTo:zoomPoint withFactor:zoomFactor animate:NO];
		}
	} else {
		if(deltaX == 0) { /// Which happens at the end of a scroll session or when fingers leave the trackpad.
			targetLabel = nil;
		} else {
			if(targetLabel) {
				/// If we are moving to the target label, we ignore scrollWheel event.
				return; /// this will not prevent appkit from calling scrollClipView: on us.
			}
		}
		
		NSEventPhase phase = theEvent.phase;
		/// if the user started to scrolls vertically, we pass the event up in the hierarchy as we don't scroll vertically
		if (phase <= NSEventPhaseBegan && vertical) {
			/// After doing so, no scrollWheel: message will be sent to us for the current scroll gesture. The next responder will "consume" the scrolling.
			[self.nextResponder scrollWheel:theEvent];
		} else {
			if(phase == NSEventPhaseEnded && fabs(previousDeltaX) >= 5 && self.allowSwipeBetweenMarkers && traceView.markerView.markerLabels.count > 0) {
				/// Here the fingers have just left the trackpad while moving (not stationary), which corresponds to a swipe gesture.
				/// We needed the previousDeltaX ivar as the deltaX is always 0 when the phase is NSEventPhaseEnded
				NSPoint location = [self convertPoint:theEvent.locationInWindow fromView:nil];
				if(NSPointInRect(location, self.horizontalRulerView.frame)) {
					if(previousDeltaX < 0) {
						targetLabel = [traceView.markerView moveToNextMarker:self];
					} else {
						targetLabel = [traceView.markerView moveToPreviousMarker:self];
					}
					if(targetLabel) {
						previousDeltaX = 0;  /// which we use to prevent scrolling in -scrollClipView: toPoint:, as the trace view has started moving to the marker independently of the scrollWheel events
						return;
					}
				}
			}
			if(NSEvent.pressedMouseButtons <= 0){
				/// we do not scroll if the mouse is down. This prevents unwanted scrolling that may happen with the magic mouse
				[super scrollWheel:theEvent];
			}
		}
		previousDeltaX = deltaX;
	}
}


- (void)magnifyWithEvent:(NSEvent *)theEvent    {
	float zoomFactor = 1+theEvent.magnification;
	NSPoint location = [traceView convertPoint:theEvent.locationInWindow fromView:nil];
	float zoomPoint = location.x;
	[traceView zoomTo:zoomPoint withFactor:zoomFactor animate:NO];
}


- (void)smartMagnifyWithEvent:(NSEvent *)theEvent {
	float zoomFactor = 4.0;
	NSPoint location = [traceView convertPoint:theEvent.locationInWindow fromView:nil];
	float zoomPoint = location.x;
	[traceView zoomTo:zoomPoint withFactor:zoomFactor animate:YES];
}


- (void)swipeWithEvent:(NSEvent *)event {
	MarkerView *markerView = (MarkerView *)self.horizontalRulerView.accessoryView;
	if(![markerView respondsToSelector:@selector(markerLabels)] || markerView.markerLabels.count == 0) {
		return;
	}
	/// We move between markers upon swipe
	float deltaX = event.deltaX;
	if(deltaX > 0) {
		[markerView moveToNextMarker:self];
	} else if(deltaX < 0) {
		[markerView moveToPreviousMarker:self];
	}
}


@end

