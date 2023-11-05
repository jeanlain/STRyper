//
//  SmartFolder.h
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
@class SampleFolder;

NS_ASSUME_NONNULL_BEGIN

/// A virtual folder that contains samples found with a search predicate.
///
/// A smart folder dynamically returns  ``Chromatogram`` objects meeting certain search criteria, like a smart folder of the macOS Finder returns files.
///
/// These search criteria are defined in a predicate associated with the smart folder.
///
/// A smart folder has no ``Folder/subfolders``, but it must have a ``Folder/parent`` of the ``SampleFolder`` class.
@interface SmartFolder : Folder {
}

/// Inits a smart folder given a parent folder an a search predicate.
///
/// This method does not check if the predicate searches for ``Chromatogram`` objects.
/// - Parameters:
///   - parent: The parent folder of the new instance.
///   - searchPredicate: The predicate used to find samples.
-(instancetype)initWithParentFolder: (SampleFolder *)parent searchPredicate:(NSPredicate *)searchPredicate;

/// The predicate the the smart folder uses to find samples.
///
/// The setter does not check of the predicate contains valid keys for ``Chromatogram`` objects.
@property (nonatomic) NSPredicate *searchPredicate;


/// The object used to store the folder 's ``searchPredicate``, as a core data attribute.
///
/// We do not use a transformable attribute for the predicate, as `NSSecureUnarchiveFromDataTransformer` is not available before macOS 10.14,
/// and not using it results in a warning message on every save.
@property (nonatomic, nullable) NSData *searchPredicateData;


/// Returns a predicated based on the ``searchPredicate`` property, but with dates comparisons corresponding to a full day rather than a specific time within this day.
///
/// This method uses `predicateWithFullDayComparisons`.
@property (nonatomic, readonly) NSPredicate *predicatedWithRoundedDates;

/// Returns samples found using the search predicate.
///
///	This getter triggers a core data fetch if the managed object context of the receiver differs from that of the ``SampleSearchHelper``.
///
///	If the contexts are the same, a new fetch may not be executed if it has been executed before.
///	Communicating with the ``SampleSearchHelper`` instance reduces the separation between the model and the UI.
@property (nullable, nonatomic, readonly) NSSet *samples;
																
/// Refreshes the content of the smart folder.
-(void)refresh;

@end

NS_ASSUME_NONNULL_END
