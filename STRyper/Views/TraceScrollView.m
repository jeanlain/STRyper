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


@implementation TraceScrollView

{
	VScaleView *vScaleView;   		/// the vertical scale view is created by us and added as a subview
	__weak TraceView *traceView;	/// A shortcut to the document view (if a traceView)
	
	/// The layer that draws our background.
	/// The default background property does not work well with animations (the background rectangle and its color are not animated).
	CALayer *backgroundLayer;
}



extern const float vScaleViewWidth;

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
			
		
 //  self.contentView.automaticallyAdjustsContentInsets = NO;
  // self.contentView.contentInsets =  NSEdgeInsetsZero;

   self.automaticallyAdjustsContentInsets = NO;
	self.contentInsets =  NSEdgeInsetsZero; // NSEdgeInsetsMake(20, 20, 20, 20);
//	self.scrollerInsets = NSEdgeInsetsMake(0, vScaleViewWidth, 0, 0);
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
	/// we override for our custom scrolling behavior
	if(traceView.hScale <= 0 || traceView.isResizing) {
		return;		/// the view being resized tends to trigger this method which messes with the scrolling. So we don't scroll in this situation.
	}
	
	BaseRange newRange = traceView.visibleRange;
	newRange.start = aPoint.x / traceView.hScale + traceView.sampleStartSize;
	/// we determine how the user is scrolling
	NSScrollerPart hitPart = self.horizontalScroller.hitPart;
	
	if(hitPart == NSScrollerIncrementPage || hitPart == NSScrollerDecrementPage) {
		/// if the user is scrolling "by page", we move the view to the newRange with animation
		/// this makes other trace views move in sync (otherwise, only the focus view would move with animation, the others would jump)
		/// and they change their vertical scale during the scroll (not after) if they autoscale to the highest visible peak
		[traceView setVisibleRange:newRange animate:YES];
	} else {
		/// else we just set the visible range
		traceView.visibleRange = newRange;
	}
}


- (void)scrollWheel:(NSEvent *)theEvent {
	BOOL vertical = fabs(theEvent.scrollingDeltaX) < fabs(theEvent.scrollingDeltaY);
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
		/// if the user started to scrolls vertically, we pass the event up in the hierarchy as we don't scroll vertically
		if (theEvent.phase <= NSEventPhaseBegan && vertical) {
			[self.nextResponder scrollWheel:theEvent];
		} else {
			/// we do not scroll if the mouse is down. This prevents unwanted scrolling that may happen with the magic mouse
			if(NSEvent.pressedMouseButtons <= 0){
				[super scrollWheel:theEvent];
			}
		}
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




@end

