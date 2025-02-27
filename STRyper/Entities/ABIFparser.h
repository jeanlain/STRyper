//
//  ABIFparser.h
//  STRyper
//
//  Created by Jean Peccoud on 04/11/2023.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A class that can parse an ABIF file and return it as a dictionary.
@interface ABIFparser : NSObject
/// The reason why we have a dedicated class for that (we could have used the Chromatogram class)
/// is its use in the quick look plugin (which cannot import the Chromatogram class as the plugin does not use core data).

/// - Returns: A dictionary whose keys are the values from `itemsToImport`, and values are decoded attributes from the file.
/// - Parameters:
///   - path: The path to the file.
///   - itemsToImport: A dictionary whose keys are the ABIF element type to import from the file (see ABIF file format specifications) appended
///     by item number (no spacer), and whose values are the keys of the returned dictionary corresponding to the item.
///   For instance, if "rawData5" is in the keys, raw fluorescence data at channel 5 will be imported.
///   - error: On output, any error that prevented parsing. In this case, the returned object may be `nil`.
+(nullable NSDictionary *)dictionaryWithABIFile:(NSString *)path itemsToImport:(NSDictionary<NSString *, NSString *> *)itemsToImport error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
