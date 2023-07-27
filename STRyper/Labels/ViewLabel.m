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
#import "AppDelegate.h"



@implementation ViewLabel


#pragma mark - initialization and base attributes setting

- (instancetype)init {
    self = [super init];
    if (self) {
		_animated = YES;
        _enabled = YES;
    }
    return self;
}


- (BOOL)tracksMouse {
	return self.enabled;
}


- (BOOL)highlightedOnMouseUp {
	return NO;
}



- (void)setView:(TraceView *)aView {
	if(_view) {
		[self removeFromView];
	}
	_view = aView;
   
}


- (void)removeFromView {
	if(_view) {
		[self removeTrackingArea];
		self.hovered = NO;
		_view = nil;
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
	if(!self.enabled) {
		return;
	}
	if (NSPointInRect(self.view.clickedPoint, self.frame)) {
		if (!self.highlightedOnMouseUp) {
			self.highlighted = YES;
		}
		self.clicked = YES;
	} else {
		self.highlighted = NO;
		self.clicked = NO;
	}
}


- (void)rightMouseDownInView {
	if(!self.enabled) {
		return;
	}
	if (NSPointInRect(self.view.rightClickedPoint, self.frame)) {
		self.highlighted = YES;
		self.clicked = YES;
	} else {
		self.highlighted = NO;
		self.clicked = NO;
	}
}


- (void)mouseUpInView {
	if(!self.enabled) {
		return;
	}
	if(NSPointInRect(self.view.mouseUpPoint, self.frame) && self.clicked) {
		self.highlighted = YES;
	}
	self.clicked = NO;
	self.dragged = NO;
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
	if(!self.view) {
		return nil;
	}
	NSRect areaFrame = NSIntersectionRect(rect, self.view.visibleRect);
	if(areaFrame.size.width > 0) {
		NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:areaFrame options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow ) owner:self userInfo:nil];
		/// we're not using the NSTrackingActiveCursorUpdate option to set the cursor as it doesn't appear helpful (especially in comparison to NSTrackingMouseEnteredAndExited). We can't reliably tell if the event correspond to the mouse entering or exiting the area
		[self.view addTrackingArea:area];
		return area;
	}
	return nil;
}


- (void)updateTrackingArea {
	TraceView *view = self.view;
	if(self.tracksMouse && view) {
		[self removeTrackingArea];
		/// when our tracking area updates, we check if we should show as hovered
		trackingArea = [self addTrackingAreaForRect:self.frame];

		self.hovered = NSPointInRect(view.mouseLocation, trackingArea.rect);
	}
}


- (void)mouseEntered:(NSEvent *)theEvent {
	self.hovered = YES;
}


- (void)mouseExited:(NSEvent *)theEvent {
	self.hovered = NO;
}



- (void)removeTrackingArea {
	TraceView *view = self.view;
	if(view && trackingArea) {
		[view removeTrackingArea:trackingArea];
		trackingArea = nil;
	}
}


# pragma mark - geometry

-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


- (void)reposition {
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	/// by default, we disable animation for a layer when the label is dragged
	if(_dragged || !_animated) {
		return NSNull.null;
	}
	return nil;
}


# pragma mark - states


-(void)setDragged:(BOOL)dragged {
	_dragged = dragged;
}


- (void)setHidden:(BOOL)hidden {
	if(self.hidden == hidden) {
		return;
	}
	_hidden = hidden;
	if(layer) {
		layer.hidden = hidden;
	} else {
		[self updateAppearance];
	}
	if(!hidden) {
		self.animated = NO;		/// when it becomes visible, the label will repositioned (below), which we don't want to animate
		[self reposition];
		self.animated = YES;
	} else {
		self.enabled = NO;
	}
}


- (void)setEnabled:(BOOL)enabled {
	if (self.enabled != enabled) {
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
		[view labelDidChangeEnabledState:self];
	}
}


- (void)setHighlighted:(BOOL)highlighted {
    if (self.highlighted != highlighted) {
        _highlighted = highlighted;
		if(highlighted) {
			self.hidden = NO;
			self.enabled = YES;			/// NOT SURE IF APPROPRIATE   TO REMOVE ?
		}
		[self updateAppearance];
		[self.view labelDidChangeHighlightedState:self];
	}
}


- (void)setHovered:(BOOL)hovered {
    if (_hovered != hovered) {
		_hovered = hovered;
		[self updateAppearance];
		[self.view labelDidChangeHoveredState:self];
    }
}


- (void)updateAppearance {
	
}


# pragma mark - other

- (void)dealloc {
	[self removeFromView];
}

@end

