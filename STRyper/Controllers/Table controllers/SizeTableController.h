//
//  SizeTableController.h
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

/// A singleton class that controls the tableview showing size standard sizes from a size standard.
///
/// In ``STRyper``,  the singleton object of this class controls the tableview showing size standard sizes  ( ``SizeStandardSize`` objects).
/// These sizes are those from the ``SizeStandard`` object that is selected in the tableview controlled by  the ``SizeTableController`` shared instance.
///
/// The singleton is loaded from a nib own by the ``SizeStandardTableController`` shared instance.
@interface SizeTableController : TableViewController


/// Adds a new ``SizeStandard/sizes`` object to the selected ``SizeStandard``.
/// - Parameter sender: The object that sent this message. It is ignored by the method.
///
/// The ``SizeStandardSize/size`` attribute of the added element is determined automatically.
-(IBAction)newSize:(id)sender;

@end

NS_ASSUME_NONNULL_END
