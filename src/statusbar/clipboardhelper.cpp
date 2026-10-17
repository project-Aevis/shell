/*
 * Copyright (C) 2021-2026 CutefishOS Team.
 * Copyright (C) 2026 Project Aevis Contributors.
 *
 * Reliable Wayland/X11 Image and Text Clipboard Helper
 */

#include "clipboardhelper.h"
#include <QDebug>

ClipboardHelper::ClipboardHelper(QObject *parent)
    : QObject(parent)
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (clipboard) {
        connect(clipboard, &QClipboard::dataChanged, this, &ClipboardHelper::onClipboardChanged);
        onClipboardChanged();
    }
}

QStringList ClipboardHelper::history() const
{
    return m_history;
}

int ClipboardHelper::count() const
{
    return m_history.size();
}

void ClipboardHelper::onClipboardChanged()
{
    if (m_internalCopy) {
        m_internalCopy = false;
        return;
    }

    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard)
        return;

    const QMimeData *mime = clipboard->mimeData(QClipboard::Clipboard);
    if (!mime)
        return;

    QString entry;

    if (mime->hasImage()) {
        QImage img = qvariant_cast<QImage>(mime->imageData());
        if (!img.isNull()) {
            QString imgDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/clipboard-images");
            QDir().mkpath(imgDir);
            QString imgPath = QStringLiteral("%1/clip_%2.png").arg(imgDir).arg(QDateTime::currentMSecsSinceEpoch());
            if (img.save(imgPath, "PNG")) {
                entry = QStringLiteral("file://") + imgPath;
            }
        }
    } else if (mime->hasText()) {
        entry = mime->text().trimmed();
    } else if (mime->hasUrls()) {
        QList<QUrl> urls = mime->urls();
        if (!urls.isEmpty()) {
            entry = urls.first().toLocalFile();
            if (entry.isEmpty())
                entry = urls.first().toString();
        }
    }

    if (entry.isEmpty())
        return;

    // Avoid duplicate at top of history
    int existing = m_history.indexOf(entry);
    if (existing == 0)
        return;

    if (existing > 0) {
        m_history.removeAt(existing);
    }

    m_history.prepend(entry);
    while (m_history.size() > 100) {
        m_history.removeLast();
    }

    emit historyChanged();
}

void ClipboardHelper::copy(const QString &item)
{
    if (item.isEmpty())
        return;

    QClipboard *clipboard = QGuiApplication::clipboard();
    m_internalCopy = true;

    // Move to top of history
    int idx = m_history.indexOf(item);
    if (idx > 0) {
        m_history.removeAt(idx);
        m_history.prepend(item);
        emit historyChanged();
    } else if (idx == -1) {
        m_history.prepend(item);
        emit historyChanged();
    }

    QString localFile = item;
    if (localFile.startsWith(QStringLiteral("file://"))) {
        localFile = QUrl(item).toLocalFile();
    }

    if (QFile::exists(localFile) && (localFile.endsWith(QStringLiteral(".png"), Qt::CaseInsensitive) || localFile.endsWith(QStringLiteral(".jpg"), Qt::CaseInsensitive))) {
        QImage img(localFile);
        if (!img.isNull() && clipboard) {
            QMimeData *mimeData = new QMimeData();
            mimeData->setImageData(img);

            QByteArray byteArray;
            QBuffer buffer(&byteArray);
            buffer.open(QIODevice::WriteOnly);
            img.save(&buffer, "PNG");
            mimeData->setData(QStringLiteral("image/png"), byteArray);

            QList<QUrl> urls;
            urls.append(QUrl::fromLocalFile(localFile));
            mimeData->setUrls(urls);
            mimeData->setText(localFile);

            clipboard->setMimeData(mimeData, QClipboard::Clipboard);
        }
    } else {
        if (clipboard) {
            clipboard->setText(item, QClipboard::Clipboard);
        }
    }

    emit itemCopied(item);
}

void ClipboardHelper::remove(int index)
{
    if (index >= 0 && index < m_history.size()) {
        m_history.removeAt(index);
        emit historyChanged();
    }
}

void ClipboardHelper::clear()
{
    if (!m_history.isEmpty()) {
        m_history.clear();
        emit historyChanged();
    }
}
