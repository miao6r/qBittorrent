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

    connect(m_ui->abortButton, &QPushButton::clicked, this, [this](){
        m_watcher->cancel();
    });
    connect(m_ui->closeButton, &QPushButton::clicked, this, [this](){
        this->close();
    });
    connect(m_ui->searchButton, &QPushButton::clicked, this, &FileSearchEntriesDialog::searchFiles);
    connect(m_ui->fixButton, &QPushButton::clicked, this, &FileSearchEntriesDialog::fixPaths);

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

extern void workerFn(QPromise<QString> &promise, const QVector<BitTorrent::Torrent *> &torrents, const bool fixPath) {
    if (!torrents.empty())
    {
        int i =0 ;
        int fixed =0;
        int skipped =0;
        int error = 0;
        int total = torrents.size();
        BitTorrent::Session* s = BitTorrent::Session::instance();
        for (BitTorrent::Torrent *torrent : torrents)
        {
            if(promise.isCanceled()) {
                break;
            }
            promise.addResult(u"(%5/%6)Torrent: %1\nCategory: %7\nSave Path: %2\nActual Storage: %3\nSearching: %4"_qs
                                       .replace(u"%1"_qs,torrent->name())
                                       .replace(u"%2"_qs,torrent->savePath().toString())
                                       .replace(u"%3"_qs,torrent->actualStorageLocation().toString())
                                       .replace(u"%4"_qs,torrent->filePaths().first().toString())
                                       .replace(u"%5"_qs,QString::number(i+1))
                                       .replace(u"%6"_qs,QString::number(total))
                                       .replace(u"%"_qs,torrent->category()));
            Path filePath = torrent->filePaths().first();
            QList<Path> visited;
            QList<QString> foundCategories;
            for(QString &category : s->categories()) {
                if(promise.isCanceled()) {
                   break;
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
                    foundCategories.append(category);
                    promise.addResult(u">>>Found in Category: %1 Path: %2"_qs.replace(u"%1"_qs, category).replace(u"%2"_qs, cpp.toString()));
                }
            }
            if(promise.isCanceled()) {
                break;
            }

            if(foundCategories.size()==1) {
                if (fixPath) {
                    bool fixCategory = false;
                    bool fixSavePath = false;
                    if(torrent->category()!=foundCategories.first()) {
                        fixCategory = true;
                    }
                    Path categorySavePath =  s->categorySavePath(foundCategories.first());
                    if( categorySavePath!= torrent->savePath()){
                        fixSavePath = true;
                    }
                    if(fixCategory || fixSavePath){
                        torrent->setAutoTMMEnabled(false);
                        torrent->setSavePath(categorySavePath);
                        torrent->setCategory(foundCategories.first());
                        promise.addResult(u"Success: fixed path and category."_qs);
                        fixed++;
                    } else {
                        promise.addResult(u"Skipped: torrent is correct."_qs);
                        skipped++;
                    }
                }
                torrent->addTag(torrent->savePath().toString().replace(u"/"_qs,u"I"_qs));
            } else if(foundCategories.size()>1) {
                for(const QString &category:foundCategories) {
                    Path  p=  s->categorySavePath(category);
                    torrent->addTag(p.toString().replace(u"/"_qs,u"I"_qs));
                }
                torrent->addTag(u"multiPaths"_qs);
                promise.addResult(u"Error: found in multiple categories."_qs);
                error++;
            } else if(foundCategories.isEmpty()){
                torrent->addTag(torrent->savePath().toString().replace(u"/"_qs,u"I"_qs));
                promise.addResult(u"No matched category."_qs);
            }

            promise.addResult(u"--"_qs);
            i++;
        }
        promise.addResult(u"===================\n %1 processed, %2 fixed, %3 skipped, %4 error, %5 total"_qs
                                  .replace(u"%1"_qs,QString::number(i))
                                  .replace(u"%2"_qs,QString::number(fixed))
                                  .replace(u"%3"_qs,QString::number(skipped))
                                  .replace(u"%4"_qs,QString::number(error))
                                  .replace(u"%5"_qs,QString::number(total)));
    }
}

void FileSearchEntriesDialog::loadTorrents(const QVector<BitTorrent::Torrent *> &torrents) {
    m_watcher->cancel();
    m_watcher->waitForFinished();
    m_torrents = torrents;
    setText(u"%1 torrents loaded.\n"_qs.replace(u"%1"_qs, QString::number(m_torrents.length())));
}

void FileSearchEntriesDialog::searchFiles() {
    m_watcher->cancel();
    m_watcher->waitForFinished();
    setText(u"Searching %1 torrents\n"_qs.replace(u"%1"_qs, QString::number(m_torrents.length())));
    m_watcher->setFuture(QtConcurrent::run(workerFn, m_torrents, false));
}

void FileSearchEntriesDialog::fixPaths() {
    m_watcher->cancel();
    m_watcher->waitForFinished();
    setText(u"Fixing %1 torrents\n"_qs.replace(u"%1"_qs, QString::number(m_torrents.length())));
    m_watcher->setFuture(QtConcurrent::run(workerFn, m_torrents, true));
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


