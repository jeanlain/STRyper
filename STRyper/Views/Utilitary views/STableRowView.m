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


- (void)setMainSubview:(NSScrollView *)mainSubView {
	if(_mainSubview) {
		[_mainSubview removeFromSuperview];
	}
	_mainSubview = mainSubView;
	if(mainSubView) {
		[self addSubview:mainSubView];
		[self registerForNotificationsWithSuperview:self.superview];
	} else if(registered) {
		[NSNotificationCenter.defaultCenter removeObserver:self];
		registered = NO;
	}
	self.needsLayout = YES;
}


-(void)registerForNotificationsWithSuperview:(NSView *)superView {
	if(!registered) {
		if([superView isKindOfClass:NSTableView.class] && superView.superview) {
			[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clipViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:superView.superview];
			registered = YES;
		}
	}
}


-(void)layout {
	[super layout];
	NSView *clipView = self.superview.superview;
	if(clipView) {
		[self setSubviewFrameWithClipView:clipView];
	}
}


- (void)viewWillMoveToSuperview:(NSView *)newSuperview {
	/// When the row view is removed (during view recycling or tableview reload) and is (or a subview) is the first responder
	/// the window may becomes the first responder, which is not what we want. It's better to make the table view the first responder.
	[super viewWillMoveToSuperview:newSuperview];
	if(newSuperview == nil) {
		NSWindow *window = self.window;
		NSResponder *firstResponder = self.window.firstResponder;
		if(firstResponder == self || ([firstResponder isKindOfClass:NSView.class] && [(NSView *)firstResponder isDescendantOf:self])) {
			[window makeFirstResponder:self.superview];
		}
	} else {
		[self registerForNotificationsWithSuperview:newSuperview];
	}
}


-(void)clipViewBoundsDidChange:(NSNotification *)notification {
	[self setSubviewFrameWithClipView:notification.object];
}


/// Makes our first subview as wide as the tableview's clip view.
-(void)setSubviewFrameWithClipView:(NSView *)clipView {
	NSView *subview = self.mainSubview;

	if(!subview) {
		return;
	}
	
	NSRect bounds = clipView.bounds;
	float xOrigin = bounds.origin.x;
	if(xOrigin < 0) {
		xOrigin = 0;
	}
	
	NSRect frame = NSMakeRect(xOrigin, 0, bounds.size.width, self.frame.size.height);
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
