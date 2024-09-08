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
	VScaleView *vScaleView;   		/// the vertical scale view is created by the scroll view and added as a subview
	__weak TraceView *traceView;	/// A shortcut to the document view (if a traceView)
	
	
	RegionLabel *targetLabel;		/// the label of the marker to which we move to after a swipe gesture
	float previousDeltaX;			/// The scrollingDeltaX of the last scrollWheel event, used to determine if we should move to the next/previous marker.
}



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
	self.hasHorizontalScroller = YES;
	self.verticalScrollElasticity = NSScrollElasticityNone;
	self.scrollerStyle = NSScrollerStyleLegacy;
	self.usesPredominantAxisScrolling = NO;
	self.borderType = NSNoBorder;
	self.rulersVisible = YES;
	self.automaticallyAdjustsContentInsets = NO;
}


- (void)setDocumentView:(__kindof NSView *)documentView {
	[super setDocumentView:documentView];
	if([self.documentView isKindOfClass:TraceView.class]) {
		traceView = self.documentView;
		if(!vScaleView) {
			vScaleView = [[VScaleView alloc] initWithFrame:NSMakeRect(0, 0, vScaleView.width, NSMaxY(self.bounds)-20) ]; /// the frame isn't  important as it is set during -tile
		}
		traceView.vScaleView = vScaleView;
		[self addSubview:vScaleView];
	} else {
		if([self.subviews containsObject:vScaleView]) {
			[vScaleView removeFromSuperview];
		}
	}
}


- (void)setScrollerStyle:(NSScrollerStyle)scrollerStyle {
	/// We enforce the legacy scroller style
	/// (if we didn't and if the user connects a magic mouse or trackpad after the app launch, the legacy scroller style could change)
	if(scrollerStyle == NSScrollerStyleLegacy) {
		[super setScrollerStyle:scrollerStyle];
	}
}


- (BOOL)isOpaque {
	return YES;
}
 

- (NSInteger)tag {
	return 10;
}




# pragma mark - tiling


- (void)tile {
	[super tile];
	/// we adjust the position of the vScaleView
	if(!vScaleView || vScaleView.isHidden) {
		return;
	}

	float topInset = 0;
	NSRulerView *rulerView = self.horizontalRulerView;
	if(rulerView && !rulerView.isHidden) {
		topInset = rulerView.frame.size.height -4 ;		/// the vScaleView slightly overlaps the ruler view to avoid clipping the topmost fluorescence level displayed.
	}
	NSRect newFrame = NSMakeRect(0, topInset, vScaleView.width, self.frame.size.height - topInset);
	if(!NSEqualRects(vScaleView.frame, newFrame)) {
		vScaleView.frame = newFrame;
		if(traceView.leftInset != vScaleView.width) {
			traceView.leftInset = vScaleView.width;
		}
	}
}

# pragma mark - user interactions

/// NOTE:  We don't use NSScrollView magnification methods as they would magnify the content in both dimensions and magnify everything, including curve thickness, labels, etc.


- (void)scrollClipView:(NSClipView *)aClipView toPoint:(NSPoint)aPoint {
	NSScrollerPart hitPart = self.horizontalScroller.hitPart;
	float hScale = traceView.hScale;
	aPoint.x += traceView.leftInset;
	
	if(traceView.isResizing || hScale <= 0) {
		return;
	}

	if(targetLabel ||
	   (previousDeltaX == 0 && (hitPart == NSScrollerNoPart || hitPart == NSScrollerKnobSlot))) {
		/// Scrolling is ignored if the trace view is already moving to a marker label or there was no scroll event initiated by the user.
		/// Because the method may have been called inappropriately, which appkit does when the trace view is resized of after a swipe between markers.
		/// The swipe requires ignoring some scrollWheel messages (inertial scrolling events after the swipe).
		/// Appkit apparently buffers these events and sees fit to call this method when the mouse exists the scrollview frame,
		/// to (apparently) make the document view scroll to where it should have scrolled if we did not ignore the scrollWheel messages.
		/// This causes a jump in scroll position.
		
		///But the scroll event can be also triggered without direct user input to allow the rubber band effect.
		///We must allow scrolling in this case.
		float traceViewWidth = traceView.bounds.size.width;
		float clipViewFrameWidth = self.contentView.frame.size.width;
		float currentPointX = aClipView.bounds.origin.x;
		if(currentPointX >= 0 && currentPointX <= traceViewWidth - clipViewFrameWidth) {
			/// Here the scroll point is within the traceView bounds, so there is no rubber band effect
			/// We ignore the scrolling.
			return;
		}
	}
	
	[traceView scrollPoint:aPoint animate:hitPart == NSScrollerIncrementPage || hitPart == NSScrollerDecrementPage];
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
			[traceView zoomTo:zoomPoint withFactor:zoomFactor animate:NO];
		}
	} else {
		if(deltaX == 0) { /// Which happens at the end of a scroll session or when fingers leave the trackpad.
			targetLabel = nil;
		} else {
			if(targetLabel) {
				/// If we are moving to the target label, we ignore scrollWheel events.
				return; /// this will not prevent appkit from calling scrollClipView: on us.
			}
		}
		
		NSEventPhase phase = theEvent.phase;
		if (phase <= NSEventPhaseBegan && vertical) {
			/// if the user started to scrolls vertically, we pass the event up in the hierarchy as we don't scroll vertically
			/// After doing so, no scrollWheel: message will be sent to us for the current scroll gesture. The next responder will "consume" the scrolling session.
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
						previousDeltaX = 0;  /// which we use to prevent scrolling in -scrollClipView: toPoint:, 
											 /// as the trace view has started moving to the marker independently of the scrollWheel events
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

