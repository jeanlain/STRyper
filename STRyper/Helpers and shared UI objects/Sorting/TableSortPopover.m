//
//  TableSortPopover.m
//  STRyper
//
//  Created by Jean Peccoud on 22/07/2023.
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


#import "TableSortPopover.h"
@import QuartzCore;
#import "SortCriteriaEditorDelegate.h"




@implementation TableSortPopover {
	__weak IBOutlet NSButton *applySortButton;
	__weak IBOutlet SortCriteriaEditor *sortCriteriaEditor;
}

	
- (instancetype)init {
	self = [super init];
	if(self) {
		[NSBundle.mainBundle loadNibNamed:@"TableSort Popover" owner:self topLevelObjects:nil];
		sortCriteriaEditor.sortCriteriaTable.backgroundColor = NSColor.clearColor;
	}
	return self;
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		[NSBundle.mainBundle loadNibNamed:@"TableSort Popover" owner:self topLevelObjects:nil];
		sortCriteriaEditor.sortCriteriaTable.backgroundColor = NSColor.clearColor;
	}
	return self;
}



- (SortCriteriaEditor *)sortCriteriaEditor {
	return sortCriteriaEditor;
}


- (SEL)sortAction {
	return applySortButton.action;
}


- (void)setSortAction:(SEL)sortAction {
	applySortButton.action = sortAction;
}


- (id)sortActionTarget {
	return applySortButton.target;
}


- (void)setSortActionTarget:(id)sortActionTarget {
	applySortButton.target = sortActionTarget;
}


/// Resizes the popover (with optional animation) so that it fits the sort criteria editor intrinsic content size.
- (void)sizeToFitWithAnimation:(BOOL)animate {
	if(!self.isShown) {
		return;
	}
	/// We fit the sort criteria editor its intrinsic height so that it doesn't have to scroll.
	/// The editor itself cannot be resized (possibly due to contraints), so, we resize ourselves, which resizes the editor.
	NSSize intrinsicContentSize = sortCriteriaEditor.intrinsicContentSize;
	CGFloat tableHeight = intrinsicContentSize.height;
	if(tableHeight < 10) {
		return;
	}
	
	/// we determine our new content height based on the difference in height of the editor and its intrinsic height
	/// We don't query our -contentSize property as it is 0 when we are not yet shown
	NSSize contentSize = sortCriteriaEditor.superview.bounds.size;
	contentSize.height += tableHeight - sortCriteriaEditor.bounds.size.height +1;
	contentSize.width = intrinsicContentSize.width;
	
	if(animate) {
		NSAnimationContext *currentContext = NSAnimationContext.currentContext;
		currentContext.allowsImplicitAnimation = YES;
		currentContext.duration = 0.2;
		currentContext.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
		[NSAnimationContext beginGrouping];
		self.contentSize = contentSize;
		[NSAnimationContext endGrouping];
	} else {
		self.contentSize = contentSize;
	}
}


- (void)showRelativeToRect:(NSRect)positioningRect ofView:(NSView *)positioningView preferredEdge:(NSRectEdge)preferredEdge {
	[super showRelativeToRect:positioningRect ofView:positioningView preferredEdge:preferredEdge];
	[self sizeToFitWithAnimation:NO];
	
}


- (void)editorDidChangeSortDescriptors:(SortCriteriaEditor *)editor {
	[self sizeToFitWithAnimation:self.animates];
}


- (void)editor:(SortCriteriaEditor *)editor didAddRowAtIndex:(NSUInteger)index {
	[self sizeToFitWithAnimation:self.animates];
	/// after inserting a row, the table is taller than its intrinsic height and shows a last empty row (for unclear reasons)
	[sortCriteriaEditor.sortCriteriaTable setFrameSize:sortCriteriaEditor.bounds.size];

}


- (void)editor:(SortCriteriaEditor *)editor didRemoveRowAtIndex:(NSUInteger)index {
	[self sizeToFitWithAnimation:self.animates];
}

@end
