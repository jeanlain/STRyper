//
//  Region.h
//  STRyper
//
//  Created by Jean Peccoud on 07/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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




#import "Trace.h"

NS_ASSUME_NONNULL_BEGIN

/// An entity that represents a particular region defined in base pairs.
///
/// A region represents a range in base pairs, with a start and end coordinate, and has a name.
///
/// This class implements methods that enable interactions with a ``RegionLabel`` object, which visually represents the region to the user.
///
/// In ``STRyper``, this class is the abstract superclass of the ``Mmarker`` and ``Bin`` classes.
@interface Region : CodingObject


/// Defines the area of a region that is the target of an action on the region.
///
/// This enum is used by ``RegionLabel``objects.
typedef NS_ENUM(NSUInteger, RegionEdge) {
	/// Represents neither of the region edges.
	noEdge,
	
	/// Denotes the left edge of the region.
	leftEdge,
	
	/// Denotes the right edge of the region.
	rightEdge,
	
	/// Represents the area between the region edges.
	betweenEdges
} ;



/// The name of the region.
@property (nonatomic, copy) NSString *name;

/// The start of the region, in base pairs.
///
/// This value should not be higher than the region's ``end`` or be negative.
@property (nonatomic) float start;

/// The end of the region, in base pairs.
///
/// This value should not be lower than the region's ``start`` or be negative.
@property (nonatomic) float end;

/// Makes the region set a suitable value for its``name``.
///
/// The default implementation do nothing.
/// Subclass can override this method, for instance to set a name that is not used by another region.
- (void) autoName;


/// Subclasses must override this method to return the regions with which the receiver must not overlap nor have the same name.
///
/// This property is used in ``allowedRangeForEdge:``.
///
/// The default implementation returns an empty array.
@property (nonatomic, readonly) NSArray<Region *> *siblings;

/// Mirrors the ``RegionLabel/editState`` of the ``RegionLabel`` class.
///
/// This property can be used/observed to change the state of a label representing the region.
@property (nonatomic) NSInteger editState;
														
/// The minimum with the region can have.
///
/// This value is used during validation of ``start`` and ``end`` attributes.
@property (nonatomic, readonly) float minimumWidth;

/// Tests whether a region overlaps with the receiver, based on their ``start`` and ``end`` attributes.
/// - Parameter region: The region for which to test the overlap with the receiver.
- (BOOL) overlapsWith:(Region *)region;


/// Tests whether the region overlaps a given range.
/// - Parameter range: The range for which to test the overlap with the receiver.
- (BOOL) overlapsWithBaseRange:(BaseRange)range;


/// Returns range that is allowed for an given edge of the region.
///
/// This returns the range of values that the ``start`` or the ``end`` attribute can take.
///
/// This default implementation returns a suitable value of the ``Mmarker`` and ``Bin`` subclasses.
/// A marker must be at least 2-bp wide, not be close than 1 bp from another marker of the same panel and channel
/// and its range must include all its bins.
///
/// A bin must be at least 0.1 bp wide, it must be distant from at least 0.05 bp from another bin or from the edge of its marker.
/// - Parameter edge: The edge for which to return range.
-(BaseRange)allowedRangeForEdge:(RegionEdge)edge;

extern CodingObjectKey regionStartKey,
regionEndKey,
regionNameKey,
regionEditStateKey;


/// A validation method for the ``start`` and ``end`` attribute, which subclasses override.
/// - Parameters:
///   - valueRef: the value to validate.
///   - isStart: Whether is the value represents the `start` or the region.
///   - error: The error to specify if validation failed.
- (BOOL)validateCoordinate:(id _Nullable *_Nullable)valueRef isStart:(BOOL)isStart error:(NSError * _Nullable*)error;

@end


@interface Region (DynamicAccessors)
/// used by subclasses (but other classes have no business of calling these. We may place them in the implementation of subclasses)

-(void)managedObjectOriginal_setName:(NSString *)name;
-(void)managedObjectOriginal_setStart:(float)start;
-(void)managedObjectOriginal_setEnd:(float)end;

@end



NS_ASSUME_NONNULL_END


