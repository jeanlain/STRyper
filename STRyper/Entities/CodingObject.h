//
//  CodingObject.h
//  STRyper
//
//  Created by Jean Peccoud on 15/11/2022.
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
#import "AppDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// A `NSManagedObject` with copying and archiving capabilities.
///
/// A `CodingObject` encodes and decodes its core data attributes  with ``encodeWithCoder:``  and ``initWithCoder:``, and implements the ``copy`` method.
///
/// Subclasses must override ``encodeWithCoder:`` and ``initWithCoder:`` to encode/decode other elements than core data attributes (including core data relationships).
///
/// This class also implements a method to test if an object has the same values for attributes as the receiver. This method can can be used in the context of unarchiving.
@interface CodingObject : NSManagedObject <NSSecureCoding, NSCopying>


/// Encodes the receiver's core data attributes that are not transient.
///
/// The attributes that are encoded are those retrieved via the `-attributesByName` property on the object's `entity`.
/// The `versionIdentifiers` of the entity's managed object model is also encoded in a key named `versionIdentifiers`.
///
/// Subclasses can override this method an call `super` to encode other elements than core data attributes, for instance relationships.
/// - Parameter coder: The encoder used to encode the receiver.
- (void)encodeWithCoder:(NSCoder *)coder;


/// Decodes the receiver's core data attributes and returns this object.
///
/// The keys that are decoded are those obtained from `-attributesByName` dictionary of the object's `entity`. Transient attributes are not decoded.
///
/// Subclasses can override this method an call `super` to decode other keys.
///
/// NOTE: the attributes are set via primitive setters, to avoid side effects.
///
/// - Important: The managed object context used to materialize the object is retrieved from the `coder`'s `delegate`, which must return a Managed object context when sent a `-childContext` message.
/// If it does not, the method tests whether the application delegate returns a context from this message. If not, the method returns `nil`.
///
/// - Parameter coder: The object used to decode the receiver.
- (instancetype)initWithCoder:(NSCoder *)coder;

/// Returns a copy of the receiver.
///
/// The method copies the object's attributes and the destinations of relationships that have a to-one reverse and a cascade delete rule.
///
/// - Important: This method tests if the destination object of a relationship implements `-copy`, but it does not test if its member do (for a collection).
/// Therefore, one must ensure that members of a to-many relationship implement `-copy`.
///
/// The copy is materialized in the receiver's managed object context.
/// The method thus returns `nil` if the receiver has no managed object context.
- (nullable id)copy;

/// Whether the object will be deleted from its context.
///
/// This property is set to `YES` in `prepareForDeletion` and is KVO compliant.
/// It can used to determine whether further changes in the object should be ignored by observes, for instance.
@property (nonatomic, readonly) BOOL willBeDeleted;

/// Returns wether an object has the same class and the same values for core data attributes as those of the receiver.
///
/// This method can be used to substitute an object with another during unarchiving.
///
/// Attributes that are compared are those obtained from the `-attributesByName` dictionary of the object's `entity`, and equality is tested with `-isEqual`.
/// Subclasses can override this method (an call super) to compare other elements.
///
/// - Parameter obj: The object to compare to the receiver.
- (BOOL)isEquivalentTo:(__kindof NSManagedObject *) obj;

/// Defines a key (e.g., name of the property of an object), used to avoid typos in code.
typedef NSString *const CodingObjectKey;

@end

extern CodingObjectKey willBeDeletedKey;

NS_ASSUME_NONNULL_END
