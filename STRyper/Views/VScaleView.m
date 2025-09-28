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


@implementation VScaleView  {
	/// We need to record the mouse location to implement the mouse drag.
	NSPoint mouseLocation;
}

@synthesize traceView = _traceView;

/// we prepare an dictionary of labels used for the ruler (expressed in base fluorescence points)
/// it makes the correspondence between an integer (fluo level) and an attributed string to draw
/// Each value is an NSArray containing an NSAttributedString + its width, and each key is a given fluo level (NSNumber).
static NSDictionary *labels;

static NSColor *rulerLabelColor;

+ (void)initialize {	
	if (self == VScaleView.class) {
		rulerLabelColor = [NSColor colorNamed:ACColorNameRulerLabelColor];
		NSDictionary *labelFontStyle = @{NSFontAttributeName: [NSFont labelFontOfSize:8.0], NSForegroundColorAttributeName: rulerLabelColor};
		
		/// we populate the dictionary.
		NSMutableDictionary *dict = NSMutableDictionary.new;
		
		int i = 10;
		for(int fluo = 0; fluo < 33000;) {
			NSAttributedString *rulerLabel = [[NSAttributedString alloc]initWithString:[NSString stringWithFormat:@"%d", fluo] attributes:labelFontStyle];
			if(fluo >= 10000) {
				rulerLabel = [[NSAttributedString alloc]initWithString:[NSString stringWithFormat:@"%dk", fluo/1000] attributes:labelFontStyle];
			}
			dict[@(fluo)] = @[rulerLabel, @(rulerLabel.size.width)];
			if (fluo == 200) i = 50;		/// for higher fluo levels, we don't generate all possible values (to save memory)
			if (fluo == 2500) i = 100;
			if (fluo == 15000) i = 500;
			fluo += i;
			
		}
		labels = [NSDictionary dictionaryWithDictionary:dict];
	}
}


- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		[self setAttributes];
	}
	return self;
}


-(void)setAttributes {
	_backgroundColor = [NSColor colorNamed:ACColorNameViewBackgroundColor];
	self.wantsLayer = YES;
	_width = 30.0;
	self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawBeforeViewResize;
}


- (TraceView *)traceView {
	if(!_traceView && [self.superview isKindOfClass:NSScrollView.class]) {
		TraceView *traceView = ((NSScrollView *)self.superview).documentView;
		if([traceView isKindOfClass:TraceView.class]) {
			_traceView = traceView;
		}
	}
	return _traceView;
}


- (void)setWidth:(CGFloat)width {
	if(width < 0) {
		width = 0;
	} else if(width > 100) {
		width = 100;
	}
	_width = width;
	self.traceView.leftInset = self.hidden? 0: width;
}


- (void)setHidden:(BOOL)hidden {
	if(hidden != self.hidden) {
		super.hidden = hidden;
		self.traceView.leftInset = hidden? 0: self.width;
	}
}



- (BOOL)clipsToBounds {
	return YES;
}


- (void)drawRect:(NSRect)dirtyRect {
	[_backgroundColor setFill];
	NSRect bounds = self.bounds;
	NSRectFill(bounds);
	TraceView *traceView = self.traceView;
	CGFloat vScale = traceView.vScale;
	if(vScale <=0) {
		return;
	}
	
	CGFloat maxX = NSMaxX(bounds);
	[rulerLabelColor set];
	NSRectFill(NSMakeRect(maxX-1, 0, 1, NSMaxY(bounds)-3));

	int labelIncrement = rulerLabelIncrementForVScale(vScale);
	for (int fluo = 0; fluo <= traceView.topFluoLevel; fluo += labelIncrement ) {
		if(fluo > 0) {
			NSArray *labelDescription = labels[@(fluo)];
			NSAttributedString *label = labelDescription.firstObject;
			float width = [labelDescription.lastObject floatValue];
			[label drawAtPoint:NSMakePoint(maxX - width - 7, fluo * vScale -4)];
		}
				
		[NSBezierPath strokeLineFromPoint:NSMakePoint(maxX - 5, fluo * vScale)
								  toPoint:NSMakePoint(maxX, fluo * vScale)]; /// main tick-mark
																			 ///
		if(fluo + labelIncrement/2 < traceView.topFluoLevel) {
			CGFloat y = (fluo + labelIncrement/2) *vScale;
			[NSBezierPath strokeLineFromPoint:NSMakePoint(maxX - 3, y)
									  toPoint:NSMakePoint(maxX, y)]; /// secondary tick-mark
		}
	}
}


/// returns the increment in size labels that is appropriate given the zoom scale.
int rulerLabelIncrementForVScale(CGFloat vScale) {
	/// This was established via trial & error. There's certainly a more flexible way to do it
	CGFloat scale = 1/vScale * 20;
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
	NSRect bounds = self.bounds;
	CGFloat y = bounds.origin.y;
	bounds.origin.y = 0;
	bounds.size.height += y;
	NSRect rect = NSIntersectionRect(bounds, self.visibleRect);
	[self addCursorRect:rect cursor:NSCursor.openHandCursor];
	
}


- (void)mouseDown:(NSEvent *)theEvent {
	mouseLocation = [self convertPoint:theEvent.locationInWindow fromView:nil];
	if(mouseLocation.y >= 0) {
		[NSCursor.closedHandCursor set];
	}
}

- (void)mouseDragged:(NSEvent *)event {
	/// We remember  the previous location of the mouse to determine the amount of change in the scale
	CGFloat previousY = mouseLocation.y;
	mouseLocation = [self convertPoint:event.locationInWindow fromView:nil];
	if(mouseLocation.y < 0) {
		return;
	}
	CGFloat newTopFluo = self.traceView.topFluoLevel * fabs(previousY)/fabs(mouseLocation.y);
	if(newTopFluo > SHRT_MAX * 1.2) {
		newTopFluo = SHRT_MAX * 1.2;
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


- (BOOL)isOpaque {
	return YES;
}


- (NSInteger)tag {
	return 5;
}

@end
