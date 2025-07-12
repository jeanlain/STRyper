//
//  NSSplitViewController+SplitViewControllerAdditions.h
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



@import Cocoa;

NS_ASSUME_NONNULL_BEGIN

/// Adds convenience methods to toggle panes of a split-view.
@interface NSSplitViewController (SplitViewControllerAdditions)

/// Toggles the pane number which corresponds to the sender's tag
- (void)togglePane:(id)sender;

/// Toggles the pane that is at index `number`
- (void)togglePaneNumber:(NSInteger)number;


@end

NS_ASSUME_NONNULL_END
