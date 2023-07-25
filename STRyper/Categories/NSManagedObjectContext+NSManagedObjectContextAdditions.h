//
//  NSManagedObjectContext+NSManagedObjectContextAdditions.h
//  STRyper
//
//  Created by Jean Peccoud on 08/02/2023.
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



#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSManagedObjectContext (NSManagedObjectContextAdditions)

/// Returns a managed object based on a string derived from its objectID.
/// If the object is not found or does not correspond to the expected class, returns `nil`.
-(nullable __kindof NSManagedObject *)objectForURIString:(NSString *)URIString expectedClass:(Class)class;
																									


/// Tries to saving the context after undoing changes successively (if the context as an undo manager)
/// tries at least one undo before the first save (this assumes that there was an validation error preventing saving)
/// When the method returns, the context should have no change to save
/// returns whether the the context could save without rolling back
-(BOOL)trySavingWithUndo;

@end

NS_ASSUME_NONNULL_END
