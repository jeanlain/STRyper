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

static NSTimer *timer;  	   /// to restore the holding priority of a pane after toggling its visibility


- (void)togglePane:(id)sender {
	/// the button tag encodes which item to collapse
	if([sender respondsToSelector:@selector(tag)]) {
		[self togglePaneNumber:[sender tag]];
	}
}


-(void)togglePaneNumber:(NSInteger)number {
	NSArray<NSSplitViewItem *> *splitViewItems = self.splitViewItems;
	NSInteger itemCount = splitViewItems.count;
	if(itemCount > number && number >= 0) {
		NSSplitViewItem *item = splitViewItems[number];
		if(!item.canCollapse && !item.isCollapsed) {
			return;
		}
		
		/// when a pane with low holding priority is revealed, it doesn't regain its original width, only its minimum thickness (and the animation fails)
		/// This may be expected behavior, as this item shouldn't induce the resizing of other items.
		/// To avoid that, we temporarily increase the item's holding priority before it reveals
		float holdingPriority = item.holdingPriority;
		BOOL restorePriority = NO;	/// This will tell whether we should restore the holding priority of the item.
		
		if(timer.isValid) {
			/// if the timer is valid (the item's visibility has just been changed) the current holding priority on the item may not be the "intrinsic" priority it is supposed to have.
			/// We retrieve it from the timer's user info.
			NSArray *userInfo = timer.userInfo;
			if([userInfo isKindOfClass:NSArray.class]) {
				NSSplitViewItem *splitViewItem = userInfo.firstObject;
				if(splitViewItem == item) {
					NSNumber *priority = userInfo.lastObject;
					if([priority isKindOfClass:NSNumber.class]) {
						holdingPriority = priority.floatValue;
					}
					[timer invalidate];    /// If we left the timer, it might fire in the middle of an animation and stop it
					restorePriority = YES; /// To avoid that, we will schedule a new timer.
				}
			}
		}
		
		if(item.collapsed && ((number == itemCount-1 && number > 0) || (number == 0 && itemCount > 1))) {
			NSInteger neighborIndex = number == 0? 1 : number-1;
			float neighborHoldingPriority = splitViewItems[neighborIndex].holdingPriority;
			if(item.holdingPriority < neighborHoldingPriority) {
				item.holdingPriority = neighborHoldingPriority + 1.0;
				restorePriority = YES;
			}
		}
		item.animator.collapsed = !item.animator.collapsed;
		
		if(restorePriority) {
			timer = [NSTimer scheduledTimerWithTimeInterval:1.0
													 target:self
												   selector:@selector(restorePriority)
												   userInfo:@[item, @(holdingPriority)]
													repeats:NO];
		}
	}
}


- (void)restorePriority {
	NSArray *userInfo = timer.userInfo;
	if([userInfo isKindOfClass:NSArray.class]) {
		NSSplitViewItem *item = userInfo.firstObject;
		NSNumber *priority = userInfo.lastObject;
		if([item isKindOfClass:NSSplitViewItem.class] && [priority isKindOfClass:NSNumber.class]) {
			item.holdingPriority = priority.floatValue;
		}
	}
}



@end
