//
//  SampleTableController.h
//  STRyper
//
//  Created by Jean Peccoud on 06/08/2022.
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



#import "TableViewController.h"
@class SampleFolder, Chromatogram;

NS_ASSUME_NONNULL_BEGIN

/// This singleton class controls the tableview listing samples.
///
/// This class manages a tableview showing samples  (``Chromatogram`` entities).
///
/// In the context of STRyper, these samples (content of the object's ``TableViewController/tableContent`` controller) are those contained in the ``SourceListController/selectedFolder``.
///
/// This class implements internal methods that allow the user to apply a ``SizeStandard`` or a ``Panel`` to target samples.
@interface SampleTableController : TableViewController


/// Contains samples being dragged from the tableview.
///
/// This method is used to drag samples between folders,
/// as the application does not yes implement pasteboard support for ``Chromatogram`` objects
@property (nonatomic, readonly) NSArray <Chromatogram *> *draggedSamples;
																			

/// Returns the receiver's ``TableViewController/tableContent``.
///
/// This merely allows using a name that is more explicit, since the ``TableViewController/tableView`` shows samples.
@property (nonatomic, readonly) NSArrayController *samples;


///  Presents an open panel allowing the user to import samples in the selected folder.
///
///  If the user validates the import, this method calls ``addSamplesFromFiles:toFolder:`` using the ``SourceListController/selectedFolder`` .
- (IBAction)showImportSamplePanel:(id)sender;


/// Imports samples (``Chromatogram`` objects) from abif files and adds it to a folder.
///
/// This method calls ``FileImporter/importSamplesFromFiles:completionHandler:`` and show errors that may have occurred to the user.
/// - Parameters:
///   - filePaths: The paths of abif files to be imported.
///   - folder: The folder to which samples should be added.
-(void) addSamplesFromFiles:(NSArray <NSString *>*)filePaths toFolder:(SampleFolder *)folder;


/// Copies of the samples referenced in the pasteboard to the selected folder.
///
/// The samples to paste are retrieved from the pasteboard if it declares the `ChromatogramPasteBoardType`.
/// This method can be used to copy and paste ``Chromatogram`` objects.
/// - Parameter sender: The object that sent the message. It is ignored by the method.
-(IBAction)paste:(id)sender;

/// The paste board type for Chromatogram objects.
///
/// We do not copy chromatograms to the pasteboard, only their the absolute string of their object id.
extern NSPasteboardType _Nonnull const ChromatogramCombinedPasteboardType;


@end



NS_ASSUME_NONNULL_END
