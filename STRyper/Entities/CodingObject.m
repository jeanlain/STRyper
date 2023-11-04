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
	for (NSString * attributeName in self.entity.attributesByName.allKeys) {
		[coder encodeObject:[self valueForKey:attributeName] forKey:attributeName];
	}
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
		delegate = NSApp.delegate;
	}
	
	if ([delegate respondsToSelector:@selector(childContext)]) {
		MOC = [delegate childContext];
	}
	
	if(!MOC) {
		return nil;
	}
	
	self = [self initWithEntity:self.entity insertIntoManagedObjectContext:MOC];
	if(self) {
		[self.entity.attributesByName enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
			NSAttributeDescription *desc = (NSAttributeDescription *)obj;
			id value = [coder decodeObjectOfClass:NSClassFromString(desc.attributeValueClassName) forKey:key];
			if(value != nil) {
				[self setPrimitiveValue:value forKey:key];
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
