//
//  MarkerTableController.h
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

NS_ASSUME_NONNULL_BEGIN

/// A singleton class that controls a tableview showing markers.
///
/// The singleton object is loaded from in the nib file owned by the ``PanelListController``.
///
/// In the context of ``STRyper``,  the ``TableViewController/tableContent`` of by this object
/// contains markers ( ``Mmarker`` objects)  of the selected ``Panel`` from the source list managed by the ``PanelListController``.
///
/// This class has internal methods that allows the user to create markers and to drag them between panels.
@interface MarkerTableController : TableViewController


@end

NS_ASSUME_NONNULL_END
