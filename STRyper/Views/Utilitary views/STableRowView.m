//
//  STableRowView.m
//  STRyper
//
//  Created by Jean Peccoud on 18/04/2023.
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



#import "STableRowView.h"

@implementation STableRowView {
	/// To know if we have already registered to a notification.
	BOOL registered;
	
}


- (void)viewDidMoveToWindow {
	if(!registered) {
		/// We need to react when the tableview scrolls.
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(setSubviewFrame:) name:NSViewBoundsDidChangeNotification object:self.enclosingScrollView.contentView];
		registered = YES;
	}
}




-(void)layout {
	[super layout];
	[self setSubviewFrame:nil];
}


/// Makes our first subview as wide as the tableview's clip view.
-(void)setSubviewFrame:(NSNotification *)notification {
	/// We obtain the visible width of our tableview
	/// for that, we use the clipview of the tableview's scrollview.
	NSView *clipView = self.enclosingScrollView.contentView;
	if(!clipView) {
		return;
	}
	
	float xOrigin = clipView.bounds.origin.x;
	if(xOrigin < 0) {
		xOrigin = 0;
	}

	NSView *subview = self.subviews.firstObject;
	if(!subview) {
		return;
	}
	
	NSRect frame = NSMakeRect(xOrigin, 0, clipView.frame.size.width, self.frame.size.height);
	NSRect subviewFrame = subview.frame;
	if (frame.size.width > 30 && (fabs(frame.origin.x - subviewFrame.origin.x) > 0.5 ||
								fabs(frame.size.width - subviewFrame.size.width) > 0.5)) {
		subview.frame = frame;
	}
}


- (void)keyDown:(NSEvent *)event {
	/// we intercept up/down arrow key events, which our tableview may consume for nothing useful, 
	/// while the user may expect to select the previous/next sample as if the source tableview was active.
	NSString *characters = event.characters;
	if(characters.length > 0) {
		unichar key = [characters characterAtIndex:0];
		if (key == NSUpArrowFunctionKey || key == NSDownArrowFunctionKey) {
			[self.window keyDown:event];
			return;
		}
	}
	[super keyDown:event];
}


- (void)dealloc {
	if(registered) {
		[NSNotificationCenter.defaultCenter removeObserver:self];
	}
}


@end
