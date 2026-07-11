//
//  MainWindowController.h
//  STRyper
//
//  Created by Jean Peccoud on 11/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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
#import "GeneratedAssetSymbols.h"
@class TableViewController;

NS_ASSUME_NONNULL_BEGIN

/// A singleton class that controls  ``STRyper``'s main window, which it populates by loading other controller objects owning nib files.
///
/// The singleton object is the responder of event messages not consumed before they reach the main window.
/// It also determines which ``TableViewController`` object provides content to the detailed outline view (``DetailedViewController``),
/// and records/restores selected items of certain tables when the selected folder changes.
@interface MainWindowController : NSWindowController <NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation, NSToolbarItemValidation, NSTabViewDelegate>

/// Returns the singleton object loaded from a nib.
+(instancetype)sharedController;

/// The controller of the main split view, which occupies the whole window.
///
/// The split view is configured to implement a behavior similar to Apple Mail.
@property (nonatomic, readonly) NSSplitViewController *mainSplitViewController;

/// The controller of the middle pane, which is a vertical split view.
@property (nonatomic, readonly) NSSplitViewController *verticalSplitViewController;


/// The controller of the tableview whose selected rows serve as source for the viewer.
///
/// Changing his property changes the content sent to the viewer.
/// The content is taken from the selected objects of the ``TableViewController/selectedObjects`` property of the sourceController.
///
/// Only the ``SampleTableController``, the ``GenotypeTableController`` and the ``MarkerTableController`` are valid sources.
@property (weak, nonatomic) TableViewController *sourceController;

/// Records the ``sourceController`` so that it can be restore in the next application launch.
-(void)recordSourceController;

/// A panel that can be used to show an error log.
///
/// This panel only contains an `NSTextView`.
@property (readonly, nonatomic) NSPanel *errorLogWindow;

/// Sets log as the text of the ``errorLogWindow``.
/// - Parameter log: The text to be shown in the log window.
-(void)setLogWindowText:(NSString *)log;

/// Shows the ``errorLogWindow``.
/// - Parameter sender: The object that sent this message. It is ignored by the method.
- (IBAction)showErrorLogWindow:(id)sender;

/// Populates the text content of the ``errorLogWindow`` with the failure reason of an error.
///
/// If the `error`'s `userInfo` dictionary contains errors at the `NSDetailedErrorsKey`, the failure reasons for these errors are logged.
/// - Parameter error: The error that should be shown in the log window.
/// - Returns: The string shown in the ``errorLogWindow``.
-(NSString *)populateErrorLogWithError:(NSError *)error;


/// Shows the user an alert based on an error, with a button that allows showing the ``errorLogWindow``.
///
/// If the `error` describes several errors in its `userInfo` dictionary, the alert will propose to show the error log window describing these errors.
/// - Parameter error: The error to show in the alert.
-(void)showAlertForError:(NSError *)error;


/// Actions sent by controls to the first responder and that only have one possible receiver.
/// As a window controller, this object may receives them and relay them to their target.

/// This sends ``TableViewController/moveSelectionByStep:`` to the ``sourceController``.
- (IBAction)moveSelectionByStep:(id)sender;


/// Toggles the right pane of the main split view.
- (IBAction)toggleRightPane:(id)sender;

/// Toggles the bottom pane of the vertical split view.
- (IBAction)toggleBottomPane:(id)sender;


typedef NS_ENUM(NSUInteger, tabViewItemIndex) {		/// the index of the tab view item in the bottom tab view
	// The tab showing the sample inspector
	sampleInspectorTab = 0,
	genotypeTab = 1,
	markerTab = 2,
	sizeStandardTab = 3
} ;

/// The index of the selected item of the tab view constituting the bottom pane mid section.
@property (nonatomic) NSInteger selectedTabViewItemIndex;


/// Sets the ``selectedTabViewItemIndex`` and uncollapse the pane containing the tab view if necessary;
/// - Parameter number: The index of the tab view item to activate.
- (void)selectTabViewItemAtIndex:(NSInteger)number;

/// Calls  ``selectedTabViewItemIndex`` with the sender `tag`.
/// - Parameter sender: The object that sent the message. The `sender` must return an integer to the `tag` message.
- (IBAction)selectTabViewItemAtIndexSpecifiedBy:(id)sender;

/// Calls ``SampleTableController/importSamples:``.
- (IBAction)importSamples:(id)sender;

/// Calls ``FolderListController/importFolder:``.
- (IBAction)importFolder:(id)sender;

/// Calls ``PanelListController/importPanels:``.
- (IBAction)importPanels:(id)sender;

/// Calls ``SourceListController/addFolder:`` to the ``FolderListController``.
- (IBAction)addSampleOrSmartFolder:(id)sender;

/// Calls ``FolderListController/editSmartFolder:``.
- (IBAction)editSmartFolder:(id)sender;

/// Call ``TableViewController/exportSelection:`` on a relevant target.
- (IBAction)exportSelection:(id)sender;

/// Restored the selected items and source controller saved in the user defaults
-(void) restoreSourceController;

@end

NS_ASSUME_NONNULL_END
