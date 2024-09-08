//
//  ViewLabel.m
//  STRyper
//
//  Created by Jean Peccoud on 12/01/13.
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


#import "ViewLabel.h"
#import "TraceView.h"



@implementation ViewLabel


#pragma mark - initialization and base attributes setting

- (instancetype)init {
    self = [super init];
    if (self) {
		_allowsAnimations = YES;
		_enabled = YES;
    }
    return self;
}


- (BOOL)tracksMouse {
	return self.enabled;
}


- (void)removeFromView {
	if(_view) {
		[self removeTrackingArea];
		self.hovered = NO;
		self.view = nil;
	}
	if(layer.superlayer) {
		[layer removeFromSuperlayer];
	}
}


- (NSMenu*)menu {
	return nil;
}


# pragma mark - reacting to user events


- (void)mouseDownInView {
	if(self.enabled) {
		if (NSPointInRect(self.view.clickedPoint, self.frame)) {
			if (!self.highlightedOnMouseUp) {
				self.highlighted = YES;
			}
			self.clicked = YES;
		} else {
			self.hovered = NO;
			self.highlighted = NO;
			self.clicked = NO; ///may not be needed as this is also set to no on mouseUp.
		}
	}
}


- (void)rightMouseDownInView {
	if(self.enabled) {
		if (NSPointInRect(self.view.rightClickedPoint, self.frame)) {
			self.highlighted = YES;
			self.clicked = YES;
		} else {
			self.highlighted = NO;
			self.clicked = NO;
		}
	}
}


- (void)mouseUpInView {
	if(self.enabled) {
		if(NSPointInRect(self.view.mouseUpPoint, self.frame) && self.clicked) {
			self.highlighted = YES;
		}
		self.clicked = NO;
		self.dragged = NO;
	}
}


- (void)deleteAction:(id)sender {
	
}


- (void)cancelOperation:(id)sender {
	
}


- (void)doubleClickAction:(id)sender {
	
}

- (void)drag {
	
}


# pragma mark - tracking area

- (nullable NSTrackingArea *) addTrackingAreaForRect:(NSRect)rect {
	TraceView *view = self.view;
	if(!view) {
		return nil;
	}
	/// The tracking area must be contained in the visible rectangle of the view.
	/// We use a 1-point distance to avoid interference with other views.
	NSRect areaFrame = NSIntersectionRect(rect, NSInsetRect(view.visibleRect, 1, 1));
	if(areaFrame.size.width > 0) {
		NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:areaFrame 
															options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow) owner:self userInfo:nil];
		/// we're not using the NSTrackingActiveCursorUpdate option to set the cursor as it doesn't appear helpful 
		/// (especially in comparison to NSTrackingMouseEnteredAndExited)
		/// because it doesn't tell if the event corresponds to the mouse entering or exiting the area
		[view addTrackingArea:area];
		return area;
	}
	return nil;
}


- (void)updateTrackingArea {
	[self removeTrackingArea];
	TraceView *view = self.view;
	if(self.tracksMouse && view) {
		/// when our tracking area updates, we check if we should show as hovered
		trackingArea = [self addTrackingAreaForRect:self.frame];

		self.hovered = NSPointInRect(view.mouseLocation, trackingArea.rect);
	}
}


- (void)mouseEntered:(NSEvent *)theEvent {
	if (theEvent.trackingArea == trackingArea) {
		self.hovered = YES;
	}
}


- (void)mouseExited:(NSEvent *)theEvent {
	if (theEvent.trackingArea == trackingArea) {
		self.hovered = NO;
	}
}



- (void)removeTrackingArea {
	if(trackingArea) {
		TraceView *view = self.view;
		if(view) {
			[view removeTrackingArea:trackingArea];
		}
	}
}


# pragma mark - geometry

-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


- (void)reposition {
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	/// by default, we don't animate basic geometry for a layer when the label is dragged
	if(!_allowsAnimations || _view.needsRepositionLabels || _view.hScale < 0 ||
	   (_dragged && ([event isEqualToString:@"bounds"] || [event isEqualToString:@"position"]))) {
		return NSNull.null;
	}
	return nil;
}


# pragma mark - states


-(void)setDragged:(BOOL)dragged {
	_dragged = dragged;
}


- (void)setHidden:(BOOL)hidden {
	if(_hidden != hidden) {
		_hidden = hidden;
		if(layer) {
			layer.hidden = hidden;
		}
		if(!hidden) {
			/// A label may not be repositioned when it is hidden so we reposition it when it becomes visible
			/// which we don't want to animate. 
			self.allowsAnimations = NO;
			[self reposition];
			self.allowsAnimations = YES;
		} else {
			self.enabled = NO;
		}
	}
}


- (void)setEnabled:(BOOL)enabled {
	if (_enabled != enabled) {
		_enabled = enabled;
		TraceView *view = self.view;
		if(!enabled) {
			self.hovered = NO;
			self.highlighted = NO;
			self.clicked = NO;
			[self removeTrackingArea];
		} else {
			self.hidden = NO;
			[self updateTrackingArea];
		}
		if(layer) {
			self.needsUpdateAppearance = YES;
		}
		[view labelDidChangeEnabledState:self];
	}
}


- (void)setHighlighted:(BOOL)highlighted {
    if (_highlighted != highlighted) {
        _highlighted = highlighted;
		if(highlighted) {
			self.hidden = NO;
			self.enabled = YES;			/// NOT SURE IF APPROPRIATE   TO REMOVE ?
		}
		self.needsUpdateAppearance = YES;
		[self.view labelDidChangeHighlightedState:self];
	}
}


- (void)setHovered:(BOOL)hovered {
    if (_hovered != hovered) {
		_hovered = hovered;
		self.needsUpdateAppearance = YES;
		[self.view labelDidChangeHoveredState:self];
    }
}


- (void)setNeedsUpdateAppearance:(BOOL)needsUpdateAppearance {
	if(_needsUpdateAppearance != needsUpdateAppearance) {
		_needsUpdateAppearance = needsUpdateAppearance;
		if(needsUpdateAppearance && layer) {
			/// We use the `layoutSublayersOfLayer:` method to update the label appearance.
			/// This seems appropriate to avoid redundant changes in appearance in the same cycle.
			[layer setNeedsLayout];
		}
	}
}


- (void)layoutSublayersOfLayer:(CALayer *)layer {
	if(layer == self->layer) {
		if(_needsUpdateAppearance) {
			[self updateAppearance];
			_needsUpdateAppearance = NO;
		} 
	}
}


- (void)updateAppearance {
	
}


- (void)updateForTheme {
	
}


# pragma mark - other

- (void)dealloc {
	[self removeFromView];
}

@end

