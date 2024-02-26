//
//  HoveredTableRowView.m
//  STRyper
//
//  Created by Jean Peccoud on 23/02/2023.
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



#import "HoveredTableRowView.h"

@implementation HoveredTableRowView  {
	
	/// to detect when the mouse enters and exits the view. A group row certainly has a way of detecting that since it shows the disclosure triangle when hovered, but it doesn't receive mouseEntered by default.
	NSTrackingArea *trackingArea;
	
	/// the rightmost table cell view that the row shows. We may resize it to avoid overlap with the custom button
	__weak NSTableCellView *cellView;
	
	/// The outline button (disclosure triangle). We place the custom button at its left, if present, or at the right of the row view
	/// IMPORTANT: it is assumed that the outline button is the only other NSButton subview of the row view.
	__weak NSButton *outlineButton;

}


- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	if(trackingArea) {
		[self removeTrackingArea:trackingArea];
	}
	if(self.hoveredButton) {
		trackingArea = [[NSTrackingArea alloc] initWithRect:NSInsetRect(self.visibleRect, 10, 0)		/// the tracking rectangle is slightly narrower than the visible rect,  to correspond to the tracking rectangle used to show the outline button
													options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:self userInfo:nil];
		[self addTrackingArea:trackingArea];
		NSPoint mouseLocation = self.window.mouseLocationOutsideOfEventStream;
		mouseLocation = [self convertPoint:mouseLocation fromView:nil];
		if(!NSPointInRect(mouseLocation, trackingArea.rect) && !self.hoveredButton.hidden) {
			self.hoveredButton.hidden = YES;
			self.needsLayout = YES;
		}
	}
}


- (void)setHoveredButton:(NSButton *)hoveredButton {
	[_hoveredButton removeFromSuperview];
	_hoveredButton = hoveredButton;
	hoveredButton.hidden = YES;
	[self addSubview:hoveredButton];
	[self updateTrackingAreas];
}


- (void)mouseEntered:(NSEvent *)event {
	[super mouseEntered:event];
	if(self.isGroupRowStyle && event.trackingArea == trackingArea) {
		self.hoveredButton.hidden = NO;
		self.needsLayout = YES;
	}
}


-(void)mouseExited:(NSEvent *)event {
	[super mouseExited:event];
	if(event.trackingArea == trackingArea) {
		self.hoveredButton.hidden = YES;
		self.needsLayout = YES;
	}
}


- (void)layout {
	[super layout];
	if(!self.hoveredButton || self.hoveredButton.hidden) {
		return;
	}
	
	if(!cellView || !outlineButton) {
		for(NSView *view in self.subviews) {
			if(view != self.hoveredButton) {
				if([view isKindOfClass:NSButton.class]) {
					outlineButton = (NSButton *)view;
				} else if([view isKindOfClass:NSTableCellView.class]) {
					/// in principle, there should be a single cell view (in a group row), but in case there are several, we take the rightmost one.
					if(!cellView || NSMaxX(view.frame) > NSMaxX(cellView.frame)) {
						cellView = (NSTableCellView *)view;
					}
				}
			}
		}
	}
	

	/// we place the hoveredButton between the rightMost cell view and the outlineButton (which is assumed to be at the right), if present
	/// we don't use auto-layout to arrange the hoveredButton and other views, because we cannot make assumptions about the presence of other views (which could be removed).
	/// there may be a flexible solution using auto-layout, but it don't see a simple one.
		
	BOOL outlineButtonShown = outlineButton && !outlineButton.isHidden;
	float width = self.hoveredButton.intrinsicContentSize.width;

	if(outlineButtonShown && NSMinX(outlineButton.frame)-5 < width) {
		self.hoveredButton.hidden = YES;
		NSLog(@"HoveredRowView cannot show the hoveredButton");
		return;
	}
	
	
	float xOrigin = outlineButtonShown? NSMinX(outlineButton.frame) -width -5 : NSMaxX(self.bounds) - width - 10;
	[self.hoveredButton setFrame: NSMakeRect(xOrigin, 0, width, self.frame.size.height)];
	
	if(cellView) {
		NSRect frame = cellView.frame;
		NSRect intersect = NSIntersectionRect(frame,  NSInsetRect(self.hoveredButton.frame, -5, 0));
		if(intersect.size.width > 0) {
			frame.size.width -= intersect.size.width;
			cellView.frame = frame;
		}
	}
}

@end
