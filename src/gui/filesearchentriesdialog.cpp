/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2019  Mike Tzou (Chocobo1)
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

#include "filesearchentriesdialog.h"

#include <algorithm>

#include <QHash>
#include <QVector>
#include <QThread>
#include <QFuture>
#include <QFutureWatcher>
#include "base/bittorrent/session.h"
#include "base/bittorrent/torrent.h"
#include "base/bittorrent/trackerentry.h"
#include "ui_filesearchentriesdialog.h"
#include "utils.h"

#define SETTINGS_KEY(name) u"FileSearchEntriesDialog/" name

FileSearchEntriesDialog::FileSearchEntriesDialog(QWidget *parent)
    : QDialog(parent)
    , m_ui(new Ui::FileSearchEntriesDialog)
    , m_storeDialogSize(SETTINGS_KEY(u"Size"_qs))
{
    m_ui->setupUi(this);

    connect(m_ui->buttonBox, &QDialogButtonBox::clicked, this, [this](QAbstractButton *button){
        if (button->text().contains(u"Abort"_qs)) {
            m_watcher->cancel();
        } else {
            this->close();
        }
    });

    m_watcher = new QFutureWatcher<QString>;
    m_watcher->setPendingResultsLimit(10);
    connect(m_watcher, &QFutureWatcherBase::resultsReadyAt, this, &FileSearchEntriesDialog::updateResults);
    loadSettings();
}

FileSearchEntriesDialog::~FileSearchEntriesDialog()
{
    saveSettings();
    if(m_watcher) {
        m_watcher->cancel();
        m_watcher->deleteLater();
    }
    delete m_ui;
}


void FileSearchEntriesDialog::appendText(const QString &text)
{
    m_ui->plainTextEdit->appendPlainText(text);
}

extern void searchFn(QPromise<QString> &promise, const QVector<BitTorrent::Torrent *> &torrents) {
    if (!torrents.empty())
    {
        int i =0 ;
        BitTorrent::Session* s = BitTorrent::Session::instance();
        for (const BitTorrent::Torrent *torrent : torrents)
        {
            if(promise.isCanceled()) {
                return;
            }
            promise.addResult(u"Torrent: %1\nSave Path: %2\nActual Storage: %3\nSearching: %4"_qs
                                       .replace(u"%1"_qs,torrent->name())
                                       .replace(u"%2"_qs,torrent->savePath().toString())
                                       .replace(u"%3"_qs,torrent->actualStorageLocation().toString())
                                       .replace(u"%4"_qs,torrent->filePaths().first().toString()));
            Path filePath = torrent->filePaths().first();
            sleep(10);
            //s->categories();
            QList<Path> visited;
            for(QString &category : s->categories()) {
                if(promise.isCanceled()) {
                    return;
                }
                Path cpath = s->categorySavePath(category);
                if(visited.contains(cpath)){
                    promise.addResult(category + u" skipped"_qs);
                    continue;
                } else {
                    visited.append(cpath);
                }
                Path cpp = (cpath/filePath);
                if (cpp.exists()) {
                    promise.addResult(u" >>>Found: Category: %1 Path: %2"_qs.replace(u"%1"_qs, category).replace(u"%2"_qs, cpp.toString()));
                } else {
                    promise.addResult(u" ---Category: %1 Path: %2"_qs.replace(u"%1"_qs, category).replace(u"%2"_qs, cpath.toString()));
                }
            }
            i++;
            if (i>50) {
                promise.addResult(u"Too many torrents, rest ignored."_qs);
            }
        }
    }
}

void FileSearchEntriesDialog::search(const QVector<BitTorrent::Torrent *> &torrents) {
    m_watcher->setFuture(QtConcurrent::run(searchFn, torrents));
}

void FileSearchEntriesDialog::setText(const QString &text)
{
    m_ui->plainTextEdit->setPlainText(text);
}

QString FileSearchEntriesDialog::text() const
{
    return m_ui->plainTextEdit->toPlainText();
}

void FileSearchEntriesDialog::saveSettings()
{
    m_storeDialogSize = size();
}

void FileSearchEntriesDialog::loadSettings()
{
    if (const QSize dialogSize = m_storeDialogSize; dialogSize.isValid())
        resize(dialogSize);
}

void FileSearchEntriesDialog::updateResults(int begin, int end)
{
    for(int i = begin;i<end;i++) {
        appendText(m_watcher->resultAt(i));
    }
}


