//
//  SizeStandardTableController.h
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
@class Chromatogram, SizeStandard;


NS_ASSUME_NONNULL_BEGIN

/// A singleton class that manages a tableview showing size standards.
///
/// In ``STRyper``, the singleton object manages the tableview listing all available size standards (``SizeStandard`` objects).
///
/// This class implement internal methods that allows the user to create a size standard by duplicating an existing one,
/// and to apply a size standard by dragging it onto the sample table managed by the ``SampleTableController`` shared instance.
@interface SizeStandardTableController : TableViewController


/// Applies a size standard to samples (Chromatogram objects).
///
/// - Parameters:
///   - standard: The size standard to apply.
///   - sampleArray: The  samples that `standard` should be applied to.
- (void)applySizeStandard:(SizeStandard*) standard toSamples:(NSArray<Chromatogram *> *)sampleArray;


/// Returns an appropriate ``SizeStandard`` for a given name.
///
/// The receiver tries to find a size standard whose name matches, among those in its``TableViewController/content``.
/// If it fails, it uses a pattern based on a number like "500" in "Genescan-500".
/// If there is no match, `nil` is returned.
/// - Parameter standardName: A name.
- (nullable SizeStandard *)sizeStandardForName:(NSString *)standardName;

@end

NS_ASSUME_NONNULL_END
