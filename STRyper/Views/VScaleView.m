//
//  VScaleView.m
//  STRyper
//
//  Created by Jean Peccoud on 03/03/2022.
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



#import "VScaleView.h"
#import "DetailedViewController.h"


@implementation VScaleView  {
	/// We need to record the mouse location to implement the mouse drag.
	NSPoint mouseLocation;
}

const float vScaleViewWidth = 30.0;

/// we prepare an dictionary of labels used for the ruler (expressed in base fluorescence points)
/// it makes the correspondence between an integer (fluo level) and an attributed string to draw
/// Each value is an NSArray containing an NSAttributedString + its width, and each key is a given fluo level (NSNumber).
static NSDictionary *labels;


+ (void)initialize {	
	extern NSDictionary *gLabelFontStyle;
	
	/// we populate the dictionary.
	NSMutableDictionary *dict = NSMutableDictionary.new;

	int i = 10;
	for(int fluo = 0; fluo < 33000;) {
		NSAttributedString *rulerLabel = [[NSAttributedString alloc]initWithString:[NSString stringWithFormat:@"%d", fluo] attributes:gLabelFontStyle];
		if(fluo >= 10000) {
			rulerLabel = [[NSAttributedString alloc]initWithString:[NSString stringWithFormat:@"%dk", fluo/1000] attributes:gLabelFontStyle];
		}
		dict[@(fluo)] = @[rulerLabel, @(rulerLabel.size.width)];
		if (fluo == 200) i = 50;		/// for higher fluo levels, we don't generate all possible values (to save memory)
		if (fluo == 2500) i = 100;
		if (fluo == 15000) i = 500;
		fluo += i;
		
	}
	labels = [NSDictionary dictionaryWithDictionary:dict];
}




- (void)viewDidMoveToWindow {
	if(!self.traceView) {
		self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawBeforeViewResize;
				
		self.traceView = [self.superview viewWithTag:1];
	
		[self bind:NSHiddenBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:ShowRuler options:@{NSValueTransformerNameBindingOption : NSNegateBooleanTransformerName}];
			/// when the view doesn't show a trace, we are hidden
		[self bind:@"hidden2" toObject:self.traceView withKeyPath:@"trace" options:@{NSValueTransformerNameBindingOption : NSIsNilTransformerName}];
		
	}
	NSPoint origin = [self convertPoint:NSMakePoint(0, 1) fromView:self.traceView];
	[self setBoundsOrigin:NSMakePoint(0, -origin.y)];
	self.hidden = self.hidden; 	/// not very elegant, but it sets the bound origins of the traceView so that the trace does not show behind us
	
}


- (BOOL)clipsToBounds {
	return YES;
}


- (void)drawRect:(NSRect)dirtyRect {
	[NSColor.windowBackgroundColor setFill];
	NSRectFill(self.bounds);
	TraceView *traceView = self.traceView;
	float vScale = traceView.vScale;
	if(vScale <=0) {
		return;
	}
	int labelIncrement = [self rulerLabelIncrementForVScale:vScale];
	float topFluoLevel = NSMaxY(traceView.bounds)/ vScale;
	for (int fluo = labelIncrement; fluo <= topFluoLevel; fluo += labelIncrement ) {
		NSAttributedString *label = labels[@(fluo)][0];
		float width = [labels[@(fluo)][1] floatValue];
		[label drawAtPoint:NSMakePoint(vScaleViewWidth - width - 7, fluo * vScale -4 )];
		[NSBezierPath strokeLineFromPoint:NSMakePoint(vScaleViewWidth - 5, fluo * vScale) toPoint:NSMakePoint(NSMaxX(self.bounds), fluo * vScale)]; /// main tick-mark
		[NSBezierPath strokeLineFromPoint:NSMakePoint(vScaleViewWidth - 3, (fluo - labelIncrement/2) * vScale) toPoint:NSMakePoint(NSMaxX(self.bounds), (fluo - labelIncrement/2) * vScale)]; /// secondary tick-mark
		
		
	}
	/// a tick-mark at 0
	[NSBezierPath strokeLineFromPoint:NSMakePoint(25, 0) toPoint:NSMakePoint(NSMaxX(self.bounds), 0)];
	
}

/// returns the increment in size labels that is appropriate given the zoom scale.
- (int)rulerLabelIncrementForVScale:(float)vScale; {
	/// This was established via trial & error. There's certainly a more flexible way to do it
	float scale = 1/vScale * 20;
	if (scale < 10) return 10;
	if (scale < 50) return 50;
	if (scale < 75) return 100;
	if (scale < 150) return 250;
	if (scale < 300) return 500;
	if (scale < 1000) return 1000;
	if (scale < 2000) return 2000;
	if (scale < 5000) return 5000;
	
	return 10000;
}


- (BOOL)acceptsFirstMouse:(NSEvent *)event {
	return YES;
}



- (void)resetCursorRects {
	/// to signify that the user can adjust the vertical scale by dragging, we show the appropriate cursor
	NSRect rect = NSIntersectionRect(self.bounds, self.visibleRect);
	[self addCursorRect:rect cursor:NSCursor.openHandCursor];
	
}


- (void)mouseDown:(NSEvent *)theEvent {
	[NSCursor.closedHandCursor set];
	mouseLocation = [self convertPoint:theEvent.locationInWindow fromView:nil];
	
}

- (void)mouseDragged:(NSEvent *)event {
	/// We remember  the previous location of the mouse to determine the amount of change in the scale
	float previousY = mouseLocation.y;
	mouseLocation = [self convertPoint:event.locationInWindow fromView:nil];
	if(mouseLocation.y < 0) {
		return;
	}
	float newTopFluo = self.traceView.topFluoLevel * fabsf(previousY)/fabs(mouseLocation.y);
	if(newTopFluo > 33000) {
		newTopFluo = 33000;
	}
	[self.traceView setTopFluoLevel: newTopFluo withAnimation:NO];
	
}


- (void)mouseUp:(NSEvent *)theEvent {
	NSPoint mouseLoc = [self convertPoint:theEvent.locationInWindow fromView:nil];
	if(NSPointInRect(mouseLoc, self.visibleRect)) {
		[NSCursor.openHandCursor set];
	}
	if (theEvent.clickCount == 2) {
		/// we scale the traceView to the highest peak when double clicked
		[self.traceView scaleToHighestPeakWithAnimation:YES];
	}
}


- (void)setHidden:(BOOL)hidden {
	super.hidden = hidden;
	/// we adjust the bounds of the other subviews to accommodate us. We do it by placing their bounds' 0 x coordinate just at our right side
	
	TraceView *traceView = self.traceView;
	NSPoint traceViewOrigin = traceView.bounds.origin;
	if(hidden) {
		if(traceViewOrigin.x != 0) {
			[traceView setBoundsOrigin:NSMakePoint(0, traceViewOrigin.y)];
		}
	} else {
		float overlap = NSIntersectionRect(self.frame, traceView.superview.frame).size.width;
		[traceView setBoundsOrigin:NSMakePoint(-overlap, traceViewOrigin.y)];
	}
	
	/// we make sure, the ruler view is tiled properly after the bounds are changed
	[traceView.enclosingScrollView tile];
}



- (BOOL)isOpaque {
	return YES;
}


- (NSInteger)tag {
	return 5;
}

@end
