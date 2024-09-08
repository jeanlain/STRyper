//
//  SampleSearchHelper.h
//  STRyper
//
//  Created by Jean Peccoud on 07/12/2022.
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
@class SmartFolder, Chromatogram, SearchWindow;

NS_ASSUME_NONNULL_BEGIN

/// A singleton class that helps ``SmartFolder`` creation/edition and sample (``Chromatogram``)  search.
///
/// The singleton object configures the predicate editor of a ``SearchWindow`` with criteria
/// corresponding to the ``Chromatogram`` attributes shown in the table managed by ``SampleTableController``.
///
/// The sample search is performed via an `NSFetchedResultsController object.
///
/// This class also has a convenience method to validate text fields of a (predicate) editor.
@interface SampleSearchHelper : NSObject <NSFetchedResultsControllerDelegate>


/// Returns the singleton object.
+ (instancetype)sharedHelper;


/// The window showing the predicate editor to the user.
@property (nonatomic, readonly) SearchWindow *searchWindow;


/// A shortcut to the predicate editor of the ``searchWindow``.
@property (weak, nonatomic, readonly) NSPredicateEditor *predicateEditor;


/// A shortcut to the predicate of the ``searchWindow``.
@property (nonatomic) NSPredicate *predicate;


/// Shows the search window as a modal sheet and sets its ``predicate`` with the predicate of the provided targetFolder.
///
/// When the modal sheets ends, a completion handler is called.
///
/// Since the singleton object has a single ``SearchWindow``, it is assumed that this method is not called again before the sheet closes.
/// We only manage a single search at once.
///
/// The method assumes that the `searchPredicate` has valid terms for a sample search.
/// - Parameters:
///   - window: The window to which the search window should be attached as a modal sheet.
///   - searchPredicate: The predicate to show in the predicate editor. If nil, the method shows a default predicate using the ``Chromatogram/sampleName`` key.
///   - callbackBlock: The block called when the user dismisses the search sheet.  The `NSModalResponse` parameter specifies the button that was pressed on the search window.
/// - Returns:Whether the search window could be shown.
- (BOOL)beginSheetModalFoWindow:(NSWindow *)window withPredicate:(nullable NSPredicate *)searchPredicate completionHandler:(void (^)(NSModalResponse returnCode))callbackBlock;


/// Returns the samples found in the persistent store using the provided predicate.
///
/// The returned set do not include samples that are in the ``SourceListController/trashFolder``.
/// - Parameter predicate: The predicate to be used to find samples.
/// - Returns: The set of samples found.
- (nullable NSSet<Chromatogram *> *)samplesFoundWithPredicate:(NSPredicate *)predicate;

/// Returns the managed object context in which samples are searched.
-(NSManagedObjectContext *)managedObjectContext;


/// Returns the first error found in text fields or an editor.
///
/// An error is an empty field or an incorrect values for a number in a text field that has a number formatter.
/// This method can be used to determine whether search terms are valid.
/// - Parameter editor: an editor.
+(nullable NSError *)errorInFieldsOfEditor:(NSView *)editor;


@end



NS_ASSUME_NONNULL_END
