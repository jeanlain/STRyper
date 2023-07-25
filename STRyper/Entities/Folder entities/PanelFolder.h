//
//  PanelFolder.h
//  STRyper
//
//  Created by Jean Peccoud on 24/11/2022.
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




#import "Folder.h"

NS_ASSUME_NONNULL_BEGIN


/// A folder containing marker panels or subfolders of its own class.
///
/// Note: ``CodingObject/encodeWithCoder:``  and ``CodingObject/initWithCoder:``  are currently implement in the context of a ``SampleFolder`` unarchiving/archiving,
/// in that the ``Folder/parent`` of the receiver is encoded/decoded, not its ``Folder/subfolders``.
@interface PanelFolder : Folder

/// When its ``Folder/subfolders`` change, a panel folder posts a notification with this name to the default notification center.
extern NSNotificationName const _Nonnull PanelFolderSubfoldersDidChangeNotification;


@end

NS_ASSUME_NONNULL_END
