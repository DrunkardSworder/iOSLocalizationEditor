//
//  LocalizationsDataSource.swift
//  LocalizationEditor
//
//  Created by Igor Kulman on 30/05/2018.
//  Copyright © 2018 Igor Kulman. All rights reserved.
//

import Cocoa
import Foundation
import os

typealias LocalizationsDataSourceData = ([String], String?, [LocalizationGroup])

/**
 Data source for the NSTableView with localizations
 */
final class LocalizationsDataSource: NSObject {
    // MARK: - Properties

    private let localizationProvider = LocalizationProvider()
    private var localizationGroups: [LocalizationGroup] = []
    private var selectedLocalizationGroup: LocalizationGroup?
    private var data: [String: [String: LocalizationString?]] = [:]
    private var filteredKeys: [String] = []

    // MARK: - Actions

    /**
     Loads data for directory at given path

     - Parameter folder: directory path to start the search
     - Parameter onCompletion: callback with data
     */
    func load(folder: URL, onCompletion: @escaping (LocalizationsDataSourceData) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let localizationGroups = self.localizationProvider.getLocalizations(url: folder)
            guard localizationGroups.count > 0, let group = localizationGroups.first(where: { $0.name == "Localizable.strings" }) ?? localizationGroups.first else {
                os_log("No localization data found", type: OSLogType.error)
                DispatchQueue.main.async {
                    onCompletion(([], nil, []))
                }
                return
            }

            self.localizationGroups = localizationGroups
            let languages = self.select(group: group)

            DispatchQueue.main.async {
                onCompletion((languages, group.name, localizationGroups))
            }
        }
    }

    /**
     Selects given localization group, converting its data to a more usable form and returning an array of available languages

     - Parameter group: group to select
     - Returns: an array of available languages
     */
    private func select(group: LocalizationGroup) -> [String] {
        selectedLocalizationGroup = group

        let numberOfKeys = group.localizations.map({ $0.translations.count }).max() ?? 0

        // master localization is the one with the most translations
        let masterLocalization = group.localizations.first(where: { $0.translations.count == numberOfKeys })

        let languages = group.localizations.sorted(by: { lhs, _ in return lhs.language == masterLocalization?.language })

        data = [:]
        for key in masterLocalization!.translations.map({ $0.key }) {
            data[key] = [:]
            for language in languages {
                data[key]![language.language] = language.translations.first(where: { $0.key == key })
            }
        }

        // making sure filteredKeys are computed
        filter(by: nil)

        return languages.map({ $0.language })
    }

    /**
     Selects given group and gets available languages

     - Parameter group: group name
     - Returns: array of languages
     */
    func selectGroupAndGetLanguages(for group: String) -> [String] {
        let group = localizationGroups.first(where: { $0.name == group })!
        let languages = select(group: group)
        return languages
    }

    /**
     Filters the data by given string. Empty string means all data us included.

     Filtering is done by setting the filteredKeys property. A key is included if it matches the search string or any of its translations matches.
     */
    func filter(by searchString: String?) {
        guard let searchString = searchString, !searchString.isEmpty else {
            filteredKeys = data.keys.map({ $0 }).sorted(by: { $0<$1 })
            return
        }

        var keys: [String] = []
        for (key, value) in data {
            // include if key matches (no need to check further)
            if key.normalized.contains(searchString.normalized) {
                keys.append(key)
                continue
            }

            // include if any of the translations matches
            if value.compactMap({ $0.value }).map({ $0.value }).contains(where: { $0.normalized.contains(searchString.normalized) }) {
                keys.append(key)
            }
        }

        // sorting because the dictionary does not keep the sort
        filteredKeys = keys.sorted(by: { $0<$1 })
    }

    /**
     Gets key for speficied row

     - Parameter row: row number
     - Returns: key if valid
     */
    func getKey(row: Int) -> String? {
        return row < filteredKeys.count ? filteredKeys[row] : nil
    }

    /**
     Gets the message for specified row

     - Parameter row: row number
     - Returns: message if any
     */
    func getMessage(row: Int) -> String? {
        guard let key = getKey(row: row), let part = data[key], let firstKey = part.keys.map({ $0 }).first  else {
            return nil
        }

        return part[firstKey]??.message
    }

    /**
     Gets localization for specified language and row. The language should be always valid. The localization might be missing, returning it with empty value in that case

     - Parameter language: language to get the localization for
     - Parameter row: row number
     - Returns: localiyation string
     */
    func getLocalization(language: String, row: Int) -> LocalizationString {
        guard let key = getKey(row: row) else {
            // should not happen but you never know
            fatalError("No key for given row")
        }

        guard let section = data[key], let data = section[language], let localization = data else {
            return LocalizationString(key: key, value: "", message: "")
        }

        return localization
    }

    /**
     Updates given localization values in given language

     - Parameter language: language to update
     - Parameter key: localization string key
     - Parameter value: new value for the localization string
     */
    func updateLocalization(language: String, key: String, with value: String, message: String?) {
        guard let localization = selectedLocalizationGroup?.localizations.first(where: { $0.language == language }) else {
            return
        }
        localizationProvider.updateLocalization(localization: localization, key: key, with: value, message: message)
    }

}

// MARK: - Delegate

extension LocalizationsDataSource: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        return filteredKeys.count
    }
}
