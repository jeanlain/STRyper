//
//  SampleFolder.h
//  STRyper
//
//  Created by Jean Peccoud on 20/11/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
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
#import "Folder.h"
@class Chromatogram;

/// A folder containing other folders of the same class and/or ``Chromatogram`` objects.
///
/// A sample folder allows the user to organize  ``Chromatogram`` objects.
@interface SampleFolder : Folder

/// The samples that the folder contains.
///
/// The reverse relationship is ``Chromatogram/folder``.
///
/// This relationship is encoded in ``CodingObject/encodeWithCoder:``  and decoded in ``CodingObject/initWithCoder:``.
@property (nonatomic) NSSet <Chromatogram *> *samples;

/// Return all samples contained in the receiver, including those present in its ``Folder/subfolders``.
@property (nonatomic, readonly) NSSet <Chromatogram *> *allSamples;

/// When the ``Folder/subfolders`` of a sample folder change, it posts a notification with this name to the default notification center.
extern NSNotificationName const SampleFolderSubfoldersDidChangeNotification;

@end


@interface SampleFolder (CoreDataGeneratedAccessors)

-(void)addSamples:(NSSet *)samples;
-(void)removeSamples:(NSSet *)samples;

@end
