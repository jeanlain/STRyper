//
//  TraceOutlineView.m
//  STRyper
//
//  Created by Jean Peccoud on 10/08/2025.
//
//
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

#import "TraceOutlineView.h"
#import "LabelView.h"

@implementation TraceOutlineView 

@dynamic delegate;

# pragma mark - row selection


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(selectAll:)) {
		return [self.delegate canSelectItemsForOutlineView:self];
	}
	
	if(menuItem.action == @selector(deselectAll:)) {
		return self.numberOfRows > 0;
	}
	
	return [super validateMenuItem:menuItem];
}


- (void)selectAll:(id)sender {
	[self.delegate selectAll:sender];
}


- (void)deselectAll:(id)sender {
	[self.delegate deselectAll:sender];
}


- (void)keyDown:(NSEvent *)event {
	[self.delegate outlineView:self keyDown:event];
}


- (NSRect)visibleRectBelowHeader {
	NSRect visibleRect = self.visibleRect;
	NSTableHeaderView *header = self.headerView;
	if(!header) {
		return visibleRect;
	}
	/// If the header is present, we don't just subtract its height from the visibleRect,
	/// as the visibleRect may extend above the header up to the window's top.
	NSRect headerFrame = [self convertRect:header.bounds fromView:header];
	if(self.isFlipped) {
		visibleRect.size.height = NSMaxY(visibleRect) - NSMaxY(headerFrame);
		visibleRect.origin.y = NSMaxY(headerFrame);
	} else {
		visibleRect.size.height = headerFrame.origin.y - NSMinY(visibleRect);
	}
	return visibleRect;
}


- (NSPoint)scrollPoint {
	NSScrollView *scrollView = self.enclosingScrollView;
	if(scrollView.documentView == self) {
		NSClipView *clipView = scrollView.contentView;
		if(clipView) {
			return [self convertPoint:clipView.bounds.origin fromView:clipView];
		}
	}
	return NSZeroPoint;
}


- (NSPoint)bottomLeftPoint {
	NSScrollView *scrollView = self.enclosingScrollView;
	if(scrollView.documentView == self) {
		NSClipView *clipView = scrollView.contentView;
		if(clipView) {
			NSRect clipViewBounds = clipView.bounds;
			NSPoint bottomLeftPoint = clipView.isFlipped? NSMakePoint(clipViewBounds.origin.x, NSMaxY(clipViewBounds)):clipViewBounds.origin;
			return [self convertPoint:bottomLeftPoint fromView:clipView];
		}
	}
	return NSZeroPoint;
}


@end
