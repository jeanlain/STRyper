//
//  CALayer+CALayerAdditions.m
//  STRyper
//
//  Created by Jean Peccoud on 03/07/2025.
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


#import "CALayer+CALayerAdditions.h"
#import "LabelView.h"

@implementation CALayer (CALayerAdditions)



-(BOOL) isVisibleOnScreen {
	CALayer *layer = self;
	while (layer) {
		if (layer.hidden || layer.opacity == 0.0) {
			return NO;
		}
		
		layer = layer.superlayer;
	}
	return YES;
}


- (CGRect)visibleRectInSuperLayer:(nullable CALayer *)ancestor {

	CGRect visibleRect = self.bounds;
	CALayer *layer = self;

	while (layer.superlayer) {
		CALayer *superlayer = layer.superlayer;

		if (superlayer.masksToBounds) {
			/// We convert the super layer rect to our coordinates.
			CGRect layerRect = [self convertRect:superlayer.bounds fromLayer:superlayer];
			CGRect clippedRect = CGRectIntersection(visibleRect, layerRect);
			if (CGRectIsNull(clippedRect)) {
				return CGRectNull; /// Fully clipped
			}
			visibleRect = clippedRect;
		}
		
		if(superlayer == ancestor) {
			break;
		}

		layer = superlayer;
	}

	return visibleRect;
}


- (CALayer *)topAncestor {
	CALayer *parent = self.superlayer;
	if(!parent) {
		return self;
	}
	while(parent.superlayer) {
		parent = parent.superlayer;
	}
	return parent;
}


- (NSSet <CALayer *>*)allSublayers {
	if(!self.sublayers) {
		return NSSet.new;
	}
	NSMutableSet *sublayers = [NSMutableSet setWithArray:self.sublayers];
	for(CALayer *sublayer in self.sublayers) {
		[sublayers unionSet:sublayer.allSublayers];
	}
	return sublayers.copy;
}


- (void) drawStringInRect:(NSRect)dirtyRect ofLayer:(CALayer *)layer withClipping:(BOOL) clip {
	
	if(!layer || ![self isKindOfClass:CATextLayer.class]) {
		return;
	}
	
	CATextLayer *Self = (CATextLayer *)self;
	if(!Self.string) {
		return;
	}
	
	NSRect frame = [self convertRect:self.bounds toLayer:layer];
	if(!NSIntersectsRect(frame, dirtyRect)) {
		return;
	}
	
	NSRect clipRect = frame;
	if(clip) {
		clipRect = [self visibleRectInSuperLayer:layer];
		if(NSIsEmptyRect(clipRect)) {
			return;
		}
		clipRect = [self convertRect:clipRect toLayer:layer];
	}
	
	NSAttributedString *string = self.attributedString;
	
	if(NSContainsRect(clipRect, frame)) {
		clip = NO;
	}
	
	if(clip) {
		NSGraphicsContext *ctx = NSGraphicsContext.currentContext;
		
		[ctx saveGraphicsState];
		
		NSBezierPath *clipPath = [NSBezierPath bezierPathWithRect:clipRect];
		[clipPath addClip];
		
		[string drawInRect:frame];
		
		[ctx restoreGraphicsState];
	} else {
		[string drawInRect:frame];
	}
}



-(NSAttributedString *) attributedString {
	CATextLayer *Self = (CATextLayer *)self;
	
	if(![self isKindOfClass:CATextLayer.class]) {
		return nil;
	}
	
	NSString *string = Self.string;
	if(!string) {
		return nil;
	}
	
	NSMutableDictionary *attributes = NSMutableDictionary.new;
	NSFont *font = Self.font;
	if (font) {
		attributes[NSFontAttributeName] = [NSFont fontWithName:font.fontName size:Self.fontSize];
	}
	
	NSColor *color = [NSColor colorWithCGColor:Self.foregroundColor];
	if (color) {
		attributes[NSForegroundColorAttributeName] = color;
	}
	
	NSMutableParagraphStyle *style = NSMutableParagraphStyle.new;
	
	NSString *mode = Self.alignmentMode;
	if(mode == kCAAlignmentLeft) {
		style.alignment = NSTextAlignmentLeft;
	} else if(mode == kCAAlignmentRight) {
		style.alignment = NSTextAlignmentRight;
	} else if(mode == kCAAlignmentCenter) {
		style.alignment = NSTextAlignmentCenter;
	} else if(mode == kCAAlignmentJustified) {
		style.alignment = NSTextAlignmentJustified;
	}
	
	mode = Self.truncationMode;
	if(mode == kCATruncationEnd) {
		style.lineBreakMode = NSLineBreakByTruncatingTail;
	} else if(mode == kCATruncationStart) {
		style.lineBreakMode = NSLineBreakByTruncatingHead;
	} else if(mode == kCATruncationMiddle) {
		style.lineBreakMode = NSLineBreakByTruncatingMiddle;
	} else if(mode == kCATruncationNone) {
		style.lineBreakMode = Self.wrapped? NSLineBreakByWordWrapping : NSLineBreakByClipping;
	}
	
	attributes[NSParagraphStyleAttributeName] = style;
	
	NSAttributedString *drawString = [[NSAttributedString alloc] initWithString:Self.string attributes:attributes];
	
	return drawString;
}



@end
