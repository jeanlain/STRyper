//
//  NSSplitViewController+SplitViewControllerAdditions.m
//  STRyper
//
//  Created by Jean Peccoud on 06/01/2023.
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



#import "NSSplitViewController+SplitViewControllerAdditions.h"

@implementation NSSplitViewController (SplitViewControllerAdditions)

static float holdingPriority;  /// to store the holding priority of a split view item (see -togglePaneNumber:)


- (void)togglePane:(id)sender {
	/// the button tag encodes which item to collapse
	if([sender respondsToSelector:@selector(tag)]) {
		[self togglePaneNumber:[sender tag]];
	}
}


-(void)togglePaneNumber:(NSInteger)number {
	NSArray *splitViewItems = self.splitViewItems;
	if(splitViewItems.count > number && number >= 0) {
		NSSplitViewItem *item = splitViewItems[number];
		if(!item.canCollapse && !item.isCollapsed) {
			return;
		}
		/// when a pane with low holding priority is revealed, it doesn't regain its original width, only its minimum thickness (and the animation fails)
		/// This may be expected behavior, as this item shouldn't induce the resizing of other items.
		/// To avoid that, we temporarily increase the item's holding priority before it reveals.
		if(item.collapsed && ((number == splitViewItems.count-1 && number > 0) || (number == 0 && splitViewItems.count > 1))) {
			NSInteger neighborIndex = number == 0? 1 : number-1;
			float neighborHoldingPriority = [splitViewItems[neighborIndex] holdingPriority];
			if(item.holdingPriority < neighborHoldingPriority) {
				holdingPriority = item.holdingPriority;				/// we record the holding priority before we change it
				item.holdingPriority = neighborHoldingPriority + 1.0;
																					
				/// we restore the holding priority, but only after the animation is finished. Otherwise, the pane doesn't regain the original width
				/// This isn't elegant, but I'm not sure how to get a notification when the item has finished uncollapsing.
				[self performSelector:@selector(restorePriorityOnItem:) withObject:item afterDelay:1.0];
			}
		}
		item.animator.collapsed = !item.animator.collapsed;
	}
}


- (void)restorePriorityOnItem:(NSSplitViewItem *)item {
	item.holdingPriority = holdingPriority;
}



@end
