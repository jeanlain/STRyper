//
//  CodingObject.m
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



#import "CodingObject.h"


@implementation CodingObject


+(BOOL)supportsSecureCoding {
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	NSDictionary<NSString *, NSAttributeDescription*> *attributeDescriptions = self.entity.attributesByName;
	[attributeDescriptions enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSAttributeDescription* desc, BOOL * _Nonnull stop) {
		if(!desc.isTransient) {
			[coder encodeObject:[self valueForKey:key] forKey:key];
		}
	}];

	/// we also encode the version identifier of the model, for future uses.
	[coder encodeObject:self.entity.managedObjectModel.versionIdentifiers forKey:@"versionIdentifiers"];
}



- (instancetype)initWithCoder:(NSCoder *)coder {
	NSManagedObjectContext *MOC;
	id delegate;
	
	if([coder respondsToSelector:@selector(delegate)]) {
		delegate = ((NSKeyedUnarchiver *)coder).delegate;
	}
	
	if(!delegate) {
		delegate = AppDelegate.sharedInstance;
	}
	
	if ([delegate respondsToSelector:@selector(childContext)]) {
		MOC = [delegate childContext];
	} else if ([delegate respondsToSelector:@selector(managedObjectContext)]) {
		MOC = [delegate managedObjectContext];
	}
	
	if(!MOC) {
		return nil;
	}
	
	self = [self initWithEntity:self.entity insertIntoManagedObjectContext:MOC];
	if(self) {
		[self.entity.attributesByName enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSAttributeDescription *desc, BOOL * _Nonnull stop) {
			if(!desc.isTransient) {
				id value = [coder decodeObjectOfClass:NSClassFromString(desc.attributeValueClassName) forKey:key];
				if(value != nil) {
					[self setPrimitiveValue:value forKey:key];
				}
			}
		}];
	}
	
	return self;
}





- (BOOL) hasSameAttributesAs:(__kindof NSManagedObject *)obj {
	if (self.class != obj.class) {
		return NO;
	}
	NSDictionary *dic = [self dictionaryWithValuesForKeys:self.entity.attributesByName.allKeys];
	NSDictionary *objDic = [obj dictionaryWithValuesForKeys:obj.entity.attributesByName.allKeys];
	
	if([dic isEqualToDictionary:objDic]) {
		return YES;
	}
	return NO;
}


- (BOOL) isEquivalentTo:(__kindof NSManagedObject *) obj {
	return [self hasSameAttributesAs:obj];
}


/// This method is overridden as object validation may generate several identical errors.
/// We try to eliminate duplicates
- (BOOL)validateForUpdate:(NSError *__autoreleasing  _Nullable *)error {
	BOOL result = [super validateForUpdate:error];
	if(error == NULL) {
		return result;
	}
	NSError *theError = *error;
	if(theError) {
		NSDictionary *userInfo = theError.userInfo;
		NSArray *errors = userInfo[NSDetailedErrorsKey];
		if(errors) {
			if(errors.count > 1) {
				errors = [errors valueForKeyPath:@"@distinctUnionOfObjects.self"];
			}
			
			if(errors.count == 1) {
				*error = errors.firstObject;
			} else {
				NSMutableDictionary *info = userInfo.mutableCopy;
				info[NSDetailedErrorsKey] = errors;
				*error = [NSError errorWithDomain:theError.domain code:theError.code userInfo:[NSDictionary dictionaryWithDictionary:info]];
			}
		}
	}
	return result;
}

# pragma mark - pasteboard support and copy

NSPasteboardType _Nonnull const CodingObjectIDPasteboardType = @"org.jpeccoud.stryper.codingObjectIDPasteboardType",
CodingObjectArchivePasteboardType = @"org.jpeccoud.stryper.codingObjectArchivePasteboardType";

/// We don't implement the NSPasteboardReading protocol, because we wouldn't know which managed object context to use to init an instance from the paste board

- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	return @[CodingObjectIDPasteboardType]; /// By default, we don't include `CodingObjectArchivePasteboardType` as encoding an an object can be quite involved.
}


- (NSPasteboardWritingOptions)writingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard {
	return 0;
}


- (id)pasteboardPropertyListForType:(NSPasteboardType)type {
	if(self.isDeleted) {
		return nil;
	}
	if([type isEqualToString:CodingObjectIDPasteboardType]) {
		/// since we write the object id, we ensure that it is not temporary.
		NSManagedObjectID *objectID = self.objectID;
		if(objectID.isTemporaryID) {
			if(![self.managedObjectContext obtainPermanentIDsForObjects:@[self] error:nil]) {
				NSLog(@"Error obtaining permanent ID for object '%@': copy not made.", self.description);
				return nil;
			}
		}
		return objectID.URIRepresentation.absoluteString;
	}
	
	if([type isEqualToString:CodingObjectArchivePasteboardType]) {
		NSError *error;
		NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:NO error:&error];
		
		if(error) {
			NSLog(@"error: %@", error);
		} else {
			return archive;
		}
	}
	
	if([type isEqualToString:NSPasteboardTypeString]) {
		return self.stringRepresentation;
	}
	
	return nil;
}


- (NSString *)stringRepresentation {
	return nil;
}


- (nullable id)copy {
	NSManagedObjectContext *MOC = self.managedObjectContext;
	if(!MOC) {
		return nil;
	}
	/// we copy attributes
	NSManagedObject *copy = [NSEntityDescription insertNewObjectForEntityForName:self.entity.name inManagedObjectContext:MOC];
	for (NSString * attributeName in self.entity.attributesByName) {
		[copy setPrimitiveValue:[[self valueForKey:attributeName] copy] forKey:attributeName];
	}
	
	/// we copy the destination of any to-many relationship that has a cascade delete rule and a to-one reserve.
	/// We consider that these relationships represent objects "owned" by the receiver
	NSDictionary *relationships = self.entity.relationshipsByName;
	for (NSString * relationshipName in self.entity.toManyRelationshipKeys) {
		NSRelationshipDescription *desc = relationships[relationshipName];
		/// relationships that should not be copied may have a special key in their dictionary (set manually in the managed object model in Xcode)
		if(desc.deleteRule != NSCascadeDeleteRule || [desc.userInfo.allKeys containsObject:@"doNotCopy"]) {
			continue;
		}
		NSDictionary *objRelationships = desc.destinationEntity.relationshipsByName;
		NSString *inverse = [self.entity inverseForRelationshipKey:relationshipName];
		desc = objRelationships[inverse];
		if(desc.toMany || desc.destinationEntity != copy.entity) {
			continue;
		}
		NSSet *items = [self valueForKey:relationshipName];
		for (NSManagedObject *item in items) {
			if([item respondsToSelector:@selector(copy)]) {
				NSManagedObject *dup = [item copy];
				[dup setValue:copy forKey:inverse];
			}
		}
	}
	
	return copy;
}



- (nonnull id)copyWithZone:(nullable NSZone *)zone {
	return [self copy];
}

@end
