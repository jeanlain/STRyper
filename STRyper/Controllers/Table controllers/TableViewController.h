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
@class MainWindowController;


NS_ASSUME_NONNULL_BEGIN


/// An abstract class that implements methods used by several singleton subclasses managing tableviews in  ``STRyper``.
///
/// This class provides common methods for controller objects that are delegate/datasource of NSTableView objects.
///	Objects that compose the rows of these tables inherit from ``CodingObject``.
///
/// This class implements methods for the deletion of items representing table rows, with optional alerts that ask the user for confirmation or explain why the deletion is not allowed.
///
/// Other methods can populate the tableview with columns and cell views, based on column descriptions provided as a dictionary (see ``columnDescription``).
/// This dictionary is useful for tables that have too many columns to all be designed in a nib.
///
/// This class implements `-copy` (to the paste board) of the text content of selected rows, for subclasses that provide a ``columnDescription``
///	and for the items shown in the table if they implement the `NSPasteBoardWriting` protocol.
///
/// This class also provides  a menu for the table header view, to allow hiding/showing columns.
@interface TableViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate> {
	
	/// backs the ``tableView`` readonly property.
	///
	/// It is used so subclasses can modify it.
	__weak IBOutlet NSTableView *_tableView;
	
	/// backs the ``tableContent`` readonly property.
	///
	/// It is used so subclasses can modify it.
	IBOutlet NSArrayController *_tableContent;
}


/// The singleton instance, loaded from a nib file.
+ (instancetype)sharedController;

/// The tableview that the receiver controls.
///
/// This view may differ from the `-view` property of the receiver, but in this case, it must be a subview of it.
/// Otherwise, the receiver may not receive messages resulting from user actions on this table.
@property (weak, readonly) NSTableView *tableView;

///The controller objet providing content to the ``tableView``.
@property (readonly, nullable) NSArrayController *tableContent;

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
-(NSString *) entityName;

/// The optional dictionary describing, for each column, what cell view it should have and how to bind it with keyPaths of the items the ``tableView`` shows.
///
/// The keys are the column identifiers, the values are itself dictionaries describing the cell views (keys are of type ``ColumnDescriptorKey``).
- (nullable NSDictionary *)columnDescription;

/// Keys of the NSDictionary describing cell to make to a column of the ``TableViewController/tableView``.
typedef NSString *const ColumnDescriptorKey;
extern ColumnDescriptorKey KeyPathToBind, /// the keyPath to bind to the textField value of the cells. Value must be an NSString.
IsTextFieldEditable,		/// Whether the cell text field is editable. The value must be an NSNumber (bool).
CellViewID,					/// the identifier of the cell view, which `viewForCellPrototypes` should be able to make. Value must be an NSString.
ColumnTitle,				/// the title the column should have. Value must be an NSString.
IsColumnVisibleByDefault; 	/// Whether the column is visible by default. Value must be an NSNumber (bool).

/// When columns are generated programmatically,
/// the tableview that contains the tableCellView prototypes (by default, the receiver's ``tableView``).
@property (nonatomic, weak) NSTableView *viewForCellPrototypes;


/// The column identifiers for the column to generate, in the default column order from left to right.
///
///	These identifiers must be among the keys of the ``columnDescription`` dictionary.
///
/// This is only relevant if columns are generated programmatically.
- (nullable NSArray<NSString *> *)orderedColumnIDs;

/// Whether the ``tableView`` saves its configuration.
///
/// The default implementation returns YES;
- (BOOL) shouldAutoSaveTable;


/// Whether the header of the ``tableView`` has a menu allowing to hide/show columns (and possibly sort).
///
/// The default implementation returns NO;
- (BOOL) shouldMakeTableHeaderMenu;

/// Whether the ``tableView`` can be sorted via sort sheet (see ``showSortCriteria:``).
///
/// The default implementation returns the same value as ``shouldMakeTableHeaderMenu``.
- (BOOL) canSortByMultipleColumns;


/// Whether items should be deleted from their managed object context with the ``removeItems:`` method on the ``tableContent``.
///
/// The default implementation returns `YES`.
- (BOOL) shouldDeleteObjectsOnRemove;


/****methods used to manage addition or deletion of objects shown in the tableview***************/

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


/// A generic method that removes target items from the ``tableView``, sent from menus and buttons.
/// - Parameter sender: The object that sent the message.
///  Because this method analyzes the sender to determine which items to remove, not any sender is adequate.
- (IBAction)remove:(id)sender;


/// The items that are the target of an action on, i.e., which are at the clicked row and/or selected rows of the ``tableView``.
///
/// - Parameter sender: The object that sent the message, typically an NSMenuItem.
/// Because this method analyzes the sender to determine which items to remove, not any sender is adequate.
- (nullable NSArray *) targetItemsOfSender:(id)sender;


/// Removes items from the ``tableView``.
///
/// The default implementation remove the items from the ``tableContent``.
/// - Parameter items: The items to remove form the tableview.
- (void)removeItems:(NSArray *)items;


/// An appropriate action title for the removal of items.
///
///	The return value will be used for the title a menu item whose action is ``remove:`` and the target is the receiver.
/// The default value is "Delete " followed by the the value returned by ``nameForItem:``.
/// If this returns `nil`, the menu is hidden out and removal is prevented.
///
/// The default implementation does not check if any of the items is actually shown in the ``tableView``.
/// - Parameter items: The items that shall be removed.
- (nullable NSString *) removeActionTitleForItems:(NSArray *)items;


/// An alert to be shown to the user trying to remove some items.
///
/// The default implementation returns an alert whose informative text is the value returned by ``removeActionTitleForItems:``.
///- Parameter items: The items that shall be removed.
- (nullable NSAlert *) cautionAlertForRemovingItems:(NSArray *)items;


/// An alert telling the user that some items cannot be removed.
///
/// If this method returns `nil`, removal proceeds without showing an alert.
/// - Parameter items: The items that shall be removed.
- (nullable NSAlert *) cannotRemoveAlertForItems:(NSArray *)items;


/// The informative text to be shown on the ``cautionAlertForRemovingItems:`` alert.
///
/// The default implementation returns "This action can be undone.".
- (NSString *) cautionAlertInformativeStringForItems:(NSArray *)items;


/// The informative text to be shown on the ``cannotRemoveAlertForItems:`` alert.
///
/// The default implementation returns `nil`.
- (nullable NSString *) cannotRemoveInformativeStringForItems:(NSArray *)items;


/// Whether ``cannotRemoveAlertForItems:`` never returns an alert indicating that items cannot be removed from the table.
///
/// The default implementation returns `YES`, hence no alert is shown.
- (BOOL) canAlwaysRemove;


/// The action sent to the receiver by the ``tableView`` when it is when clicked.
///
/// Subclasses override this method to set the ``MainWindowController/sourceController``.
- (IBAction)tableViewIsClicked:(NSTableView *)sender;


/// Shows a popover that allows the user to sort the ``tableView`` by several columns.
///
/// This method uses a ``TableSortPopover``.
/// The popover is shown relative to the table header view.
- (IBAction)showSortCriteria:(id)sender;


/// Moves the selected rows of the ``tableView`` one step down or up while maintaining the number of selected rows.
- (void)moveSelectionByStep:(id)sender;



/****methods used to copy objects to the pasteboard ***************/

/// Copies the items that are selected in the ``tableView`` to the general pasteboard.
/// - Parameter sender: The object that sent this message. The default implementation ignores this parameter.
-(IBAction)copy:(id)sender;

/// Returns a string representing the values that a given object may show at the visible columns of the ``tableView``.
///
/// This method relies on ``stringCorrespondingToColumn:forObject:``:
/// - Parameter object: The object of which a string representation should be returned.
- (NSString *)stringForObject:(id) object;
														
														
/// A string corresponding to the value of a column (of the ``tableView``) for an object.
///
/// For performance reasons, the method does not read from a cell at that column and at the row represented by the object.
/// This means that the object doesn't even have to be in the ``tableContent``.
/// If the object isn't of the class managed by ``tableContent``, the returned string may not make sense.
/// - Parameters:
///   - column: The column for which the string should be returned.
///   - object: The object for which the string should be returned.
- (NSString *)stringCorrespondingToColumn:(NSTableColumn *)column forObject:(id) object;
				
/// Returns a pasteboard type for elements written to a single `NSPasteboardItem` object during ``copy:``.
///
/// If not `nil` (the default), the returned value will be attributed to a pasteboard item for a string concatenating the object IDs of copied elements, separated by newline characters.
/// If `nil`, each copied element will be represented by its own pasteboard item if it implements `NSPasteboardWriting`.
///
/// Using a single pasteboard item allows much faster reading of the pasteboard upon paste.
-(nullable NSPasteboardType)pasteboardTypeForCombinedItems;

@end

NS_ASSUME_NONNULL_END
