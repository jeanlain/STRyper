//
//  InfoTableRowView.m
//  STRyper
//
//  Created by Jean Peccoud on 28/09/2025.
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

#import "InfoTableRowView.h"

@implementation InfoTableRowView {
	__weak InfoOutlineView *infoOutlineView;
}

- (void)viewDidMoveToSuperview {
	[super viewDidMoveToSuperview];
	if([self.superview isKindOfClass:InfoOutlineView.class]) {
		infoOutlineView = (InfoOutlineView*)self.superview;
	} else {
		infoOutlineView = nil;
	}
}

- (void)drawSeparatorInRect:(NSRect)dirtyRect {
	if(!infoOutlineView.drawGridForMainSectionsOnly) {
		[super drawSeparatorInRect:dirtyRect];
		return;
	}
	
	
	id nextItem = [infoOutlineView itemAtRow:[infoOutlineView rowForView:self]+1];
	if([infoOutlineView parentForItem:nextItem] == nil) {
		[super drawSeparatorInRect:dirtyRect];
	}
}



- (void)drawBackgroundInRect:(NSRect)dirtyRect {
	if(!infoOutlineView.drawGridForMainSectionsOnly) {
		[super drawBackgroundInRect:dirtyRect];
	}
}


- (BOOL)isOpaque {
	if(!infoOutlineView.drawGridForMainSectionsOnly) {
		return super.isOpaque;
	}
	return NO;
}



@end
