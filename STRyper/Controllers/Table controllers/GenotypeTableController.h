//
//  GenotypeTableController.h
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
#import "AppDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// A singleton class that manages a tableview listing genotypes (``Genotype`` objects).
///
/// In the context of ``STRyper``, the table shows the genotypes of the ``SampleTableController/samples`` shown in the sample table (managed by the ``SampleTableController`` shared instance).
@interface GenotypeTableController : TableViewController 


/// Returns the receiver's ``TableViewController/tableContent``.
///
/// This allows using a name that is more explicit, since the table shows genotypes.
@property (nonatomic, readonly) NSArrayController *genotypes;

/// A  key to the user default that allows access to the genotype filters applied to folders
extern UserDefaultKey GenotypeFiltersKey;

/// A  key to the user default that allows recording the selected genotype in each folder
extern UserDefaultKey SelectedGenotypes;

@end

NS_ASSUME_NONNULL_END
