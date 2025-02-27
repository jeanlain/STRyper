//
//  TableViewController.h
//  STRyper
//
//  Created by Jean Peccoud on 13/02/2022.
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
#import "NSMenuItem+NSMenuItemAdditions.h"
#import "AppDelegate.h"
@class MainWindowController;


NS_ASSUME_NONNULL_BEGIN


/// An abstract class that implements methods used by several singleton subclasses managing tableviews in  ``STRyper``.
///
/// This class provides common methods for controller objects that are delegate/datasource of `NSTableView` objects.
/// Objects that compose the rows of these tables inherit from ``CodingObject``.
///
/// This class implements methods for the deletion and export of items representing table rows and to record/restore the selected items in/from the user defaults.
/// It also performs validation of menu and toolbar items, and determines which items of the table are targets.
///
/// Other methods can populate the tableview with columns and cell views, based on column descriptions provided as a dictionary (see ``columnDescription``).
/// This dictionary is useful for tables that have too many columns to all be designed in a nib.
///
/// This class implements `-copy` (to the paste board) of the text content of selected rows, for subclasses that provide a ``columnDescription``,
/// and for the items shown in the table if they implement the `NSPasteBoardWriting` protocol.
/// This class implements dragging rows of the table (see ``tableView:pasteboardWriterForRow:``.
///
/// This class also provides  a menu for the table header view, to allow hiding/showing columns and sorting via a popover of class ``TableSortPopover``.
@interface TableViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSPopoverDelegate, NSMenuItemValidation, NSToolbarItemValidation, NSViewToolTipOwner> {
	
	/// backs the ``tableView`` readonly property.
	///
	/// It is used so subclasses can modify it.
	__weak IBOutlet NSTableView *_tableView;
	
	/// backs the ``tableContent`` readonly property.
	///
	/// It is used so subclasses can modify it.
	IBOutlet NSArrayController *_tableContent;
	
	/// A popover allowing to define the filter on the table content
	NSPopover *filterPopover;
}


/// The singleton instance, loaded from a nib file.
+ (instancetype)sharedController;


#pragma mark - managing the table view

/// The tableview that the receiver manages.
///
/// This view may differ from the `view` property of the receiver, but in this case, it must be a subview of it,
/// otherwise, the receiver may not receive messages resulting from user actions on this table.
@property (weak, readonly, nonatomic) NSTableView *tableView;

///The controller objet providing content to the ``tableView``.
@property (readonly, nullable, nonatomic) NSArrayController *tableContent;

/// A method that can be overridden to configure the ``tableContent`` array controller.
///
/// This method is called at the beginning of `-viewDidLoad`.
///
/// The default implementation sets  ``entityName`` as the name of the entity controller by the ``tableContent`` controller,
/// binds the controller managed object context to the ``AppDelegate/managedObjectContext``,
/// and establishes usual bindings between the ``tableView`` and the ``tableContent``: content, selection index paths and sort descriptors.
- (void)configureTableContent;
	
/// The name of the entity that the ``tableContent`` array controller controls.
///
/// The default implementation returns the ``CodingObject`` entity name.
@property (readonly, nonatomic) NSString *entityName;

/// The optional dictionary describing, for each column, what cell view it should have and how to bind it with keyPaths of the items the ``tableView`` shows.
///
/// The keys are the column identifiers, the values are itself dictionaries describing the cell views (keys are of type ``ColumnDescriptorKey``).
@property (readonly, nullable, nonatomic) NSDictionary<NSString *, NSDictionary *> *columnDescription;

/// Keys of the NSDictionary describing cells that populate a given column the ``TableViewController/tableView``.
typedef NSString *const ColumnDescriptorKey;
extern ColumnDescriptorKey KeyPathToBind, /// the keyPath to bind to the textField value of the cells. Value must be an NSString.
IsTextFieldEditable,		/// Whether the cell text field is editable. The value must be an NSNumber (bool).
CellViewID,					/// the identifier of the cell view, which `viewForCellPrototypes` should be able to make. Value must be an NSString.
ColumnTitle,				/// the title the column should have. Value must be an NSString.
IsColumnVisibleByDefault, 	/// Whether the column is visible by default. Value must be an NSNumber (bool).
IsColumnSortingCaseInsensitive; 	/// Whether the column sorting is case-insensitive.


/// The tableview that contains the prototypes for table cell view (by default, the receiver's ``tableView``).
///
/// This method avoids defining the same cell prototype redundantly in nibs containing several table views using this prototype.
@property (nonatomic, weak) NSTableView *viewForCellPrototypes;


/// The column identifiers for the column to generate, in the default column order from left to right.
///
/// These identifiers must be among the keys of the ``columnDescription`` dictionary.
///
/// This is only relevant if columns are generated programmatically.
@property (readonly, nonatomic, nullable) NSArray<NSString *> *orderedColumnIDs;


/// The visible columns of the ``tableView``.
@property (readonly, nullable, nonatomic) NSArray<NSTableColumn *>* visibleColumns;


/// Returns whether a column of the ``tableView`` can be hidden by the user.
///
/// The default implementation returns `YES`.
/// - Parameter column: The column that may be hidden.
- (BOOL)canHideColumn:(NSTableColumn *)column;


/// Whether the ``tableView`` saves its configuration.
///
/// The default implementation returns `YES`.
@property (readonly, nonatomic) BOOL shouldAutoSaveTable;


/// Whether the header of the ``tableView`` has a menu allowing to hide/show columns (and possibly sort).
///
/// The default implementation returns `NO`.
@property (readonly, nonatomic) BOOL shouldMakeTableHeaderMenu;


/// Whether the ``tableView`` can be sorted via a sort sheet (see ``showSortCriteria:``).
///
/// The default implementation returns the same value as ``shouldMakeTableHeaderMenu``.
@property (readonly, nonatomic) BOOL canSortByMultipleColumns;


/// Whether items should be deleted from their managed object context with the ``deleteItems:`` method on the ``tableContent``.
///
/// The default implementation returns `YES`.
@property (readonly, nonatomic) BOOL shouldDeleteObjectsOnRemove;


/// The user-facing name for the type of item populating the table (used in dialogs).
///
/// The default implementation returns "Item";
- (NSString*) nameForItem:(id)item;


/// Selects the content of the text field showing the name of the selected/clicked item in the ``tableView``.
/// - Parameter sender: The object that sent the message.
- (IBAction)rename:(id)sender;


/// Returns whether an item can be renamed.
///
/// The default implementation returns `YES`.
/// - Parameter item: The item to be renamed.
-(BOOL)canRenameItem:(id)item;


/// Selects the text showing the name of the provided item in the ``tableView``.
///
/// This convenience method relies on ``itemNameColumn``, to select the name of new items for editing by the user.
- (void)selectItemName:(id)item;


/// The index of the column showing item names in  the ``tableView``.
///
/// This column is assumed to have table cell views with text fields.
///
/// The default value is 0.
- (NSInteger) itemNameColumn;


#pragma mark - deleting items


/// A generic method that removes target items from the ``tableView`` (and deletes them), sent from menus and buttons.
/// - Parameter sender: The object that sent the message, which determines the target items via ``validTargetsOfSender:``.
- (IBAction)remove:(id)sender;


/// The items that are valid targets of an action by a sender (e.g. a menu item), among those listed in the ``tableView``.
///
/// If `sender` is an item from the ``tableView``'s `menu`, the target item is the one at the row
/// that was right-clicked if it is not a selected row (or `nil` if the click occurred outside a row). Otherwise, the target items are those that are selected.
///	Otherwise, the selected objects are returned.
///
///	Subclass can override this method to perform additional checks of validity, based on the `sender`'s `action` or other properties.
///	The default implementation never returns `nil`.
/// - Parameter sender: The object that sent the message, typically an `NSMenuItem`.
/// - Important: The `sender` must respond to `action` and return a `selector`.
/// - Important: returning `nil` invalidates the `sender` in this class' implementations of `validateMenuItem:` and `validateToolbarItem:`, which call this method.
- (nullable NSArray *) validTargetsOfSender:(id)sender;


/// Removes items from the ``tableView``.
///
/// The default implementation remove the items from the ``tableContent``.
/// - Parameter items: The items to remove form the tableview.
- (void)deleteItems:(NSArray *)items;


/// An appropriate action title for the deletion of items.
///
/// The returned value is used for the title a menu item whose action is ``remove:`` and the target is the receiver.
/// The default value is "Delete " followed by the the value returned by ``nameForItem:``.
/// If this returns `nil`, the menu is hidden and removal is prevented.
///
/// The default implementation assumes that every item is shown in the ``tableView``.
/// - Parameter items: The items that shall be deleted.
- (nullable NSString *) deleteActionTitleForItems:(NSArray *)items;


/// The informative text to be shown on an alert warning the user about the deletion of items.
///
/// The default implementation returns "This action can be undone.".
/// If `nil` is returned, no alert is shown and the deletion proceeds.
/// - Parameter items: The items that shall be deleted.
- (nullable NSString *) cautionAlertInformativeStringForItems:(NSArray *)items;


/// The informative text to be shown on an alert telling that items cannot be deleted.
///
/// The default implementation returns `nil`, in which case no alert is shown and the deletion can proceed.
/// - Parameter items: The items that shall be deleted.
- (nullable NSString *) cannotDeleteInformativeStringForItems:(NSArray *)items;



#pragma mark - exporting items

/// Overridden by subclasses to allow the user to export items shown on their table.
///
/// The default implementation does nothing.
/// - Parameter sender: The object that sent the message.
- (IBAction)exportSelection:(id)sender;


/// Wether the receiver responds to ``exportSelection:``.
///
/// If this property returns `NO`, the controller will not handle ``exportSelection:``,
/// such that some next responder in the chain may handle it.
/// The default is `NO`.
@property (readonly, nonatomic) BOOL canExportItems;


/// An appropriate action title for the export of items.
///
/// The returned value is used for the title a menu item whose action is ``exportSelection:`` and the target is the receiver.
/// If this returns `nil`, the menu is hidden and export is prevented.
///
/// The default implementation return `nil` if `canExportItems` returns `NO`.
/// Otherwise, it returns "Export " followed by `nameForItem:`.
/// - Parameter items: The items that shall be exported.
- (nullable NSString *) exportActionTitleForItems:(NSArray *)items;


/// A suitable image for a toolbar button used to export items shown in the ``tableView``.
///
/// The method is used during `validateToolbarItems` and updates the image of the item.
/// The default image is a rounded square with a up arrow coming out of it. Subclasses can provide
/// an image that represents the type of items.
/// - Parameter items: The items that should be exported.
- (NSImage *) exportButtonImageForItems:(NSArray *)items;



#pragma mark - editing and selecting table cells

/// The action name to provide to the receiver's undo manager when a cell has been edited.
///
/// The default implementation returns "Edit " followed by the column title. If `nil` is returned, no action name will be set.
/// - Parameter column: The column at which text has been edited.
/// - Parameter row: The row a at which text has been edited.
- (nullable NSString *) actionNameForEditingCellInColumn:(NSTableColumn *)column row:(NSInteger)row;


/// Action that can be sent by a popup button within a cell.
///
/// The default implementation sets the undo manager's action name with
/// ``actionNameForEditingCellInColumn:row:`` if `sender` is in the ``tableView``.
/// - Parameter sender: The popup that sent the message.
- (IBAction)popupClicked:(NSPopUpButton *)sender;

/// Reveals an item by scrolling the ``tableView``  if necessary and flashes its row with a white frame.
/// - Parameter item: The item to reveal.
///
/// The method does nothing if the item is not found in the ``tableContent``'s `arrangedObjects`,
/// neither does it change the selection.
- (void)flashItem:(id)item;


/// The action sent to the receiver by the ``tableView`` when it is when clicked.
///
/// Subclasses override this method to set the ``MainWindowController/sourceController``.
- (IBAction)tableViewIsClicked:(NSTableView *)sender;


/// Shows a popover that allows the user to sort the ``tableView`` by several columns.
/// 
/// This method uses a ``TableSortPopover``.
/// The popover is shown relative to the table header view.
/// - Parameter sender: The object that sent this message. The default implementation ignores this parameter.
- (IBAction)showSortCriteria:(id)sender;


/// Moves the selected rows of the ``tableView`` one step down or up while maintaining the number of selected rows.
///
/// - Parameter sender: The object that sent this message. The default implementation ignores this parameter.
- (void)moveSelectionByStep:(id)sender;

#pragma mark - copy/paste

/// Copies the items that are selected in the ``tableView`` to the general pasteboard.
/// - Parameter sender: The object that sent this message. 
-(IBAction)copy:(id)sender;


/// Copies items from an array to the pasteboard.
///
/// The default implementation copies the text content of table rows that may show the
/// corresponding items, calling ``stringForObject:``.
/// Subclasses can override the method to add custom data to the pasteboard.
/// - Parameters:
///   - items: The items to be copied.
///   - pasteboard: The pasteboard to copy the items to.
-(void) copyItems:(NSArray *) items ToPasteBoard:(NSPasteboard *)pasteboard;


/// Implements the delegate method `tableView:pasteboardWriterForRow:`
///
/// The default implementation returns the item at the row if it conforms to `NSPasteboardWriting`.
/// If not, the method creates an `NSPasteboardItem` with the item's objectID absolute string set for
/// the type returned by ``draggingPasteBoardTypeForRow:`` if this method does not return `nil`.
///
/// Otherwise the method returns `nil` (no dragging).
- (nullable id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row;

/// The type of pasteboard to use when a row of the table is dragged.
///
/// This method is called during ``tableView:pasteboardWriterForRow:``.
/// - Parameter row: The row that is dragged.
-(nullable NSPasteboardType) draggingPasteBoardTypeForRow:(NSInteger) row;

/// Returns a string representing the values that a given object may show at the visible columns of the ``tableView``.
///
/// This method relies on ``stringCorrespondingToColumn:forObject:``:
/// - Parameter object: The object of which a string representation should be returned.
- (NSString *)stringForObject:(id) object;
														
														
/// A string corresponding to the value that a column of the ``tableView`` would show for an object.
///
/// For performance reasons, the method does not read from a table cell,
/// which means that the object doesn't even have to be in the ``tableContent``.
///
/// - Important: This method relies on the ``columnDescription`` dictionary and the object must be of the class managed by the ``tableContent``.
/// - Parameters:
///   - column: The column for which the string should be returned.
///   - object: The object for which the string should be returned.
- (NSString *)stringCorrespondingToColumn:(NSTableColumn *)column forObject:(id) object;
				

#pragma mark - recoding and restoring selection

/// Records the selected items (selected rows) in the user defaults so that selection can be preserved between app launches.
///
/// The items are recorded as an array of strings (the URI representation of their object IDs).
/// This array is stored at key `key` of an `NSDictionary` which is encoded
/// in the user defaults at the key returned by ``userDefaultKeyForSelectedItemIDs``.
/// - Parameters:
///   - key: The key of the dictionary at which the selected items are recorded (see discussion).
///   - maxRecorded: The maximum number of selected items to record. Use 0 if all items must be recorded.
-(void)recordSelectedItemsAtKey:(NSString *)key maxRecorded:(NSUInteger)maxRecorded;

/// The key to store the identifiers of selected object in the user defaults.
///
/// The returned value is used for ``recordSelectedItemsAtKey:maxRecorded:`` and ``restoreSelectedItemsAtKey:``.
/// It must not be identical to a key used in the user default from another purpose.
- (UserDefaultKey) userDefaultKeyForSelectedItemIDs;

/// Restore the selected items (selects rows) retrieved from the user defaults.
/// - Parameters:
///   - key: The key of the dictionary where identifiers for the selected object were stored (see ``recordSelectedItemsAtKey:maxRecorded:``).
-(void)restoreSelectedItemsAtKey:(NSString *)key;

/// Records the selected Items in the user defaults.
///
/// Subclass are expected to override this method and call ``recordSelectedItemsAtKey:maxRecorded:``.
-(void)recordSelectedItems;

/// Restores the selected items store in the user defaults and scrolls the ``tableView`` to show the first selected row.
///
/// Subclass are expected to override this method and call ``restoreSelectedItemsAtKey:``.
-(void)restoreSelectedItems;


#pragma mark - filtering items

/// The method below are not much generic, the merely avoid replicating code in two subclasses
/// that allow filtering the table content.

/// A button that is used to filter the table content.
@property (weak, nonatomic) IBOutlet NSButton *filterButton;

/// The default action of the ``filterButton.
///
/// The default implementation presents a `NSPopover`showing an `NSPredicateEditor`
/// relative to the ``filterButton``, only if ``filterUsingPopover`` return `YES`.
/// Otherwise the method does nothing.
/// - Parameter sender: The ``filterButton``.
- (void)filterButtonAction:(NSButton *)sender;

/// The image to show on the ``filterButton``.
///
/// The default image is similar to that used in Apple Mail (as of macOS 14) and depends
/// on the presence of a filter predicate on the ``tableContent``.
@property (nonatomic) NSImage *filterButtonImage;


/// Whether the filter to apply should be configurable by the user using a popover.
///
/// The default implementation returns `YES`.
- (BOOL)filterUsingPopover;

/// Configures the predicate editor used to filter content.
/// 
/// The method is called just before the popover used to present the filter predicate editor shows for the first time.
/// The default implementation does nothing.
/// Subclasses are expected to configure the `rowTemplates` and the `formattingDictionary`of the `predicateEditor`.
/// - Parameter predicateEditor: The predicate editor to configure.
- (void)configurePredicateEditor:(NSPredicateEditor *)predicateEditor;

/// The predicate to show in the predicate editor by default.
///
/// This method is called when there is no filter predicate applied to ``tableContent`` and the predicate editor will be shown to the user.
@property (nonatomic, readonly) NSPredicate *defaultFilterPredicate;

/// Applies a filter predicate to ``tableContent``.
///
/// This method is called when the user applies the predicate configure in the popover, using a validation button.
/// If the predicate is the same as already applied the method calls `rearrangeObject` on ``tableContent``.
/// Subclasses can override this method and perform additional actions.
/// - Parameter filterPredicate: The filter predicate to apply.
- (void)applyFilterPredicate:(nullable NSPredicate *)filterPredicate;


@end

NS_ASSUME_NONNULL_END
