//
//  PanelListController.h
//  STRyper
//
//  Created by Jean Peccoud on 07/08/2022.
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



#import "SourceListController.h"
#import "MarkerTableController.h"

NS_ASSUME_NONNULL_BEGIN
/// A singleton class that manages and source list of ``PanelFolder`` and ``Panel`` objects.
///
/// This class complements its superclass with internal methods allowing the user to import/export panels, to add new markers (``Mmarker`` objects) and to copy-drop markers into panels.
@interface PanelListController : SourceListController 


/// Shows an open panel allowing the user to import ``Panel`` objects from a text file and add them to a target folder
///
/// The panels are imported if the user validates, and any error that may have occurred is shown.
/// - Parameter sender: The object that sent this message. It is used to infer the destination folder of the importer panels.
- (IBAction)importPanels:(id)sender;

/// Applies a marker panel to samples (Chromatogram objects).
///
/// The method displays an alert to notify the user if samples lack adequate channel data for markers of the panel.
/// - Parameters:
///   - panel: The panel to apply.
///   - sampleArray: The  samples that `panel` should be applied to.
- (void)applyPanel:(Panel*) panel toSamples:(NSArray<Chromatogram *>*)sampleArray;


/// Returns a hierarchical menu that list the available panel in their folder.
///
/// Menu items will have the action `applyPanel:`.
/// - Parameters:
///   - target: The targets of menu items in the menu.
///   - fontSize: The size of font for the menu.
-(nullable NSMenu *) menuForPanelsWithTarget:(id) target fontSize:(CGFloat)fontSize;

@end

NS_ASSUME_NONNULL_END
