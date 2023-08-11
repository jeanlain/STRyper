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


/// Shows an open panel allowing the user to import a ``Panel`` object from a text file.
///
/// The panel is imported if the user validates, and any error that may have occurred is shown.
/// - Parameter sender: The object that sent this message. It is ignored by the method.
- (IBAction)importPanel:(id)sender;

@end

NS_ASSUME_NONNULL_END
