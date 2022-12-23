/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2020  Vladimir Golovnev <glassez@yandex.ru>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * In addition, as a special exception, the copyright holders give permission to
 * link this program with the OpenSSL project's "OpenSSL" library (or with
 * modified versions of it that use the same license as the "OpenSSL" library),
 * and distribute the linked executables. You must obey the GNU General Public
 * License in all respects for all of the code used other than "OpenSSL".  If you
 * modify file(s), you may extend this exception to your version of the file(s),
 * but you are not obligated to do so. If you do not wish to do so, delete this
 * exception statement from your version.
 */

#include "filesearcher.h"
#include "base/bittorrent/common.h"
#include "base/bittorrent/infohash.h"

void FileSearcher::search(const BitTorrent::TorrentID &id, const PathList &originalFileNames
                          , const Path &savePath, const Path &downloadPath, const bool forceAppendExt,  const bool skipChecking, const QList<QPair<QString, Path>> *categoryPaths)
{
    const auto findAll = [](const Path &dirPath, PathList &fileNames, bool allowIncomplete) -> bool
    {
        for (Path &fileName : fileNames)
        {
            if (!(dirPath / fileName).exists())
            {
                if(!allowIncomplete) {
                    return false;
                }
                const Path incompleteFilename = fileName + QB_EXT;
                if (!(dirPath / incompleteFilename).exists())
                {
                    return false;
                }
            }

        }
        return true;
    };
    const auto findInDir = [](const Path &dirPath, PathList &fileNames, const bool forceAppendExt) -> bool
    {
        bool found = false;
        for (Path &fileName : fileNames)
        {
            if ((dirPath / fileName).exists())
            {
                found = true;
            }
            else
            {
                const Path incompleteFilename = fileName + QB_EXT;
                if ((dirPath / incompleteFilename).exists())
                {
                    found = true;
                    fileName = incompleteFilename;
                }
                else if (forceAppendExt)
                {
                    fileName = incompleteFilename;
                }
            }
        }

        return found;
    };
    QString category;
    Path usedPath = savePath;
    PathList adjustedFileNames = originalFileNames;
    bool skipping = skipChecking;
    // search savePath for completed files first
    PathList searchList;
    searchList.append(originalFileNames.first());
    bool found = findAll(usedPath, searchList, true);
    if (!found && categoryPaths) {
        // search category paths for completed files
        for(const QPair<QString, Path> &cp : *categoryPaths) {
            QString c = cp.first;
            Path p = cp.second;
            QString ps = p.toString();
            if(findAll(p, searchList, true)) {
                category = c;
                usedPath = p;
                skipping = true;
                break;
            }
        }
    }

    if (skipChecking || skipping) {
        qsizetype l = originalFileNames.length();
        int step = l/10;
        step = step<1?1:step;
        for (int i=0; i< l;i+=step) {
            searchList.append(originalFileNames.at(i));
        }
        skipping = findAll(usedPath, adjustedFileNames, false);
    }

    if(!skipping) {
        found = findInDir(usedPath, adjustedFileNames, (forceAppendExt && downloadPath.isEmpty()));
        if (!found && !downloadPath.isEmpty())
        {
            usedPath = downloadPath;
            findInDir(usedPath, adjustedFileNames, forceAppendExt);
        }
    }
    emit searchFinished(id, usedPath, adjustedFileNames, category, skipping);
}
