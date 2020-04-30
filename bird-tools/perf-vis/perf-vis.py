#!/usr/bin/python3

from PySide2.QtCore import Qt, QAbstractTableModel, QAbstractListModel, QModelIndex, QSortFilterProxyModel, QRect, QSize, Signal, Slot, QMimeData
from PySide2.QtWidgets import QApplication, QWidget, QTableView, QVBoxLayout, QHBoxLayout, QPushButton, QFileDialog, QCheckBox, QLabel, QAction, QAbstractItemView, QFrame
from PySide2.QtGui import QPainter, QPen, QColor, QBrush, QDrag, QFontMetrics, QImage, QPixmap

# Create the app
import sys
import math
import random
from datetime import datetime 
app = QApplication(sys.argv)

sortedDataSetRole   = Qt.UserRole + 0
groupByRole         = Qt.UserRole + 1
indexRole           = Qt.UserRole + 2

# The Model for data
class PerfLogModel(QAbstractTableModel):
    colHeads = [ "count", "file", "time", "version", "test", "exp" ]
    expIndex = 5
    groupingChanged = Signal(())
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._data = []
        self._rawData = []
        self._indices = []
        self.dataHeads = []
        self.dataHeadIndex = {}
        self.dataHeadOffset = len(self.colHeads)
        self.aggregateBy = { "time" }
        self.groupBy = [ key for key in self.colHeads[1:] if key not in self.aggregateBy ]
        self.normalize = False

    def rowCount(self, parent=None):
        return len(self._data)

    def columnCount(self, parent=None):
        return len(self.dataHeads) + self.dataHeadOffset

    def headerData(self, section, orientation, role):
        if role != Qt.DisplayRole:
            return None

        if orientation == Qt.Horizontal:
            if section < self.dataHeadOffset:
                return self.colHeads[section]
            else:
                return self.dataHeads[section - self.dataHeadOffset]

        return None

    def columnIndex(self, name):
        for i in range(self.dataHeadOffset):
            if name == self.colHeads[i]:
                return i

        if name in self.dataHeadIndex:
            return self.dataHeadIndex[name] + self.dataHeadOffset

        raise Exception("There is no column called " + name)

    def data(self, index, role):
#        print("data", index, role)

        if index is None:
            return None

        row = index.row()
        col = index.column()

        if row < 0 or row >= self.rowCount():
            return None

        if col < 0 or col >= self.columnCount():
            return None

        if col < self.dataHeadOffset:
            if role == Qt.DisplayRole:
                return self._data[row][col]
            else:
                return None

        if role == Qt.DisplayRole:
            return "%(d).3f" % { "d": self._data[row][col]["avg"] }
        elif role == Qt.ToolTipRole:
#            print(self._indices[row])
            return "%(idx)s; σ = %(d).3f" % {
                    "d": self._data[row][col]["sd"],
                    "idx": "\n".join([
                        "%(k)s\t= %(v)s" % {"k": k, "v": v}
                        for k,v in self._indices[row].items()
                        ])
                    }
        elif role == sortedDataSetRole:
            return self._data[row][col]
        elif role == groupByRole:
            gb = "\n".join([
                str(self._indices[row][key])
                for key in self.groupBy
                ])
            return gb
        elif role == indexRole:
            return self._indices[row]

    def recountAggregated(self):
        # Recounting the data according to the aggregation requested
        self.beginResetModel()
        self.aggregatedIndex = {}
        self._data = []
        self._indices = []

        for row in self._rawData:
            idx = self.aggregatedIndex
            # prepend the Count field
            newRow = [1] + row

            for colIndex in range(len(self.colHeads), self.columnCount()):
                val = float(newRow[colIndex])
                if self.normalize:
                    val /= 2**newRow[self.expIndex]
                newRow[colIndex] = { "data": [ val ] }

#            print("adding another row: ", newRow)
            idxlist = {}
            for colIndex in range(1, len(self.colHeads)):
                if self.colHeads[colIndex] in self.aggregateBy:
#                    print("aggregating by ", self.colHeads[colIndex])
                    continue

                idxlist[self.colHeads[colIndex]] = newRow[colIndex]

                if newRow[colIndex] not in idx:
                    idx[newRow[colIndex]] = {}
                idx = idx[newRow[colIndex]]

            if "row" not in idx:
#                print("index not found")
                idx["row"] = len(self._data)
                self._data.append( newRow )
                self._indices.append( idxlist )
            else:
                rowIndex = idx["row"]
#                print("index found: ", rowIndex)
                oldRow = self._data[rowIndex]
                oldRow[0] += 1
                for colIndex in range(1, len(self.colHeads)):
                    if oldRow[colIndex] is not None and oldRow[colIndex] != newRow[colIndex]:
                        oldRow[colIndex] = None
                for colIndex in range(len(self.colHeads), self.columnCount()):
                    oldRow[colIndex]["data"].append( newRow[colIndex]["data"][0] )

        for row in self._data:
            for colIndex in range(len(self.colHeads), self.columnCount()):
#                print(row)
                cnt = row[0]
                lsum = 0.0
                qsum = 0.0
                row[colIndex]["data"].sort()
                for d in row[colIndex]["data"]:
                    lsum += d
                    qsum += d*d
                if cnt > 1:
                    row[colIndex]["sd"] = math.sqrt((qsum / cnt) - (lsum / cnt)**2)
                else:
                    row[colIndex]["sd"] = None
                row[colIndex]["avg"] = lsum / cnt

        self.endResetModel()

    def toggleNormalize(self, val):
        if self.normalize == val:
            return

        self.normalize = val
        self.recountAggregated()

    def toggleAggregator(self, what, state):
        if state == (what in self.aggregateBy):
            return

        if state:
            self.aggregateBy.add(what)
            self.groupBy = [ key for key in self.groupBy if key != what ]
        else:
            self.aggregateBy.discard(what)
            self.groupBy.append(what)

#        print(self.aggregateBy, self.groupBy)

        self.groupingChanged.emit()
        self.recountAggregated()

    def moveGrouper(self, what, newpos):
#        print("MoveGrouper", what, newpos)

        oldpos = None
        for i in range(len(self.groupBy)):
            if self.groupBy[i] == what:
                oldpos = i
        
        if oldpos == newpos or oldpos == newpos - 1:
            return

        if oldpos < newpos:
            gbn = self.groupBy[0:oldpos] + self.groupBy[oldpos+1:newpos] + [ what ] + self.groupBy[newpos:]
        else:
            gbn = self.groupBy[0:newpos] + [ what ] + self.groupBy[newpos:oldpos] + self.groupBy[oldpos+1:]

#        print(self.groupBy, oldpos, newpos, what, gbn)

        self.groupBy = gbn
        self.groupingChanged.emit()
        self.beginResetModel()
        self.endResetModel()

    def addFile(self, f):
        with open(f, 'r') as fp:
            for line in fp:
                line = line.strip()
                items = line.split(" ")
                date = items.pop(0)
                time = items.pop(0)
                if items.pop(0) != "<INFO>":
                    continue
                if items.pop(0) != "Perf":
                    continue
                version = items.pop(0)
                test = items.pop(0)
                exp = items.pop(0)
                if exp.startswith("exp="):
                    exp = exp[4:]
                elif exp == "done" or exp == "starting":
                    continue
                else:
                    print("strange exp value: " + exp)
                    continue
                if items.pop(0) != "times:":
                    print("garbled line")
                    continue
                row = [
                        f,
                        date + " " + time,
                        version,
                        test,
                        int(exp)
                        ]
                while len(items):
                    item = items.pop(0)
                    kv = item.split("=")
                    if len(kv) != 2:
                        print("garbled line: " + item)
                        continue
                    if kv[0] in self.dataHeadIndex:
                        di = self.dataHeadIndex[kv[0]]
                    else:
                        di = len(self.dataHeads)
                        self.beginInsertColumns(QModelIndex(), di, di)
                        self.dataHeadIndex[kv[0]] = di
                        self.dataHeads.append(kv[0])
                        self.endInsertColumns()

                    row.insert(di + self.dataHeadOffset, int(kv[1]))

                self._rawData.append(row)

        self.recountAggregated()

#    def flags(self, *args, **kwargs):
#        print("Model", "flags", args, "kwargs", kwargs)
#        out = super().flags(*args, **kwargs)
#        print("returns", out)
#        return out

#    def __getattribute__(self, *args, **kwargs):
#        print("Model", "getattribute", args, "kwargs", kwargs)
#        out = super().__getattribute__(*args, **kwargs)
#        print("returns", out)
#        return out

class PerfLogAggregableController(QWidget):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.layout = QHBoxLayout(self)
        self.layout.addWidget(QLabel(text = "Aggregate by: "))
        self.togglers = []

    def setModel(self, model):
        for t in self.togglers:
            self.layout.removeWidget(t)

        self.togglers = []
        self.model = model
        cols = self.model.colHeads[1:]

        for c in cols:
            t = QCheckBox(text = c)
            t.setChecked(c in self.model.aggregateBy)
            t.stateChanged.connect(self.stateChangedFactory(c))
            self.layout.addWidget(t)

    def stateChangedFactory(self, what):
        def stateChanged(state):
            self.model.toggleAggregator(what, (state == Qt.Checked))
        return stateChanged

class PerfGroupLabel(QLabel):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.setLineWidth(1)
        self.setFrameStyle(QFrame.Box)
        self.setMargin(3)

    def sizeHint(self):
        out = super().sizeHint()
        nw = out.height() * 5
        return QSize(nw, out.height())

    def sizePolicy(self):
        return QSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)

class PerfGrouperDragData(QMimeData):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._gdata = None

    def setGrouperData(self, data):
        self._gdata = data

    def getGrouperData(self):
        return self._gdata

class PerfGrouper(QWidget):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.layout = QHBoxLayout(self)
        self.layout.addStretch(1)
        self.layout.addWidget(QLabel(text = "Group by: "))
        self.model = None
        self.groupers = []
        self.setAcceptDrops(True)

    def mousePressEvent(self, event):
#        print("mouse press event", event)
        child = self.childAt(event.pos())

        if child is None:
            return

        hotspot = event.pos() - child.pos()

        dd = PerfGrouperDragData()
        dd.setGrouperData({
            "child": child,
            })

        d = QDrag(self)
        d.setMimeData(dd)
        d.setHotSpot(hotspot)
#        d.setPixmap(child.pixmap())

        res = d.exec_(Qt.MoveAction, Qt.MoveAction)

    def dragEnterEvent(self, event):
        if type(event.mimeData()) == PerfGrouperDragData:
            event.acceptProposedAction()

    def dropEvent(self, event):
#        print("dropEvent", event)
        dd = event.mimeData()
        moved = dd.getGrouperData()["child"]

#        print("ep", event.pos())

        index = 0
        for g in self.groupers:
            if g.pos().x() > event.pos().x():
                break
            else:
                index += 1

        return self.model.moveGrouper(moved.text(), index)

    def setModel(self, model):
        if self.model is not None:
            self.model.groupingChanged.disconnect(self.updateLabels)

        self.model = model
        self.model.groupingChanged.connect(self.updateLabels)
        self.updateLabels()

    @Slot()
    def updateLabels(self):
        for g in self.groupers:
            self.layout.removeWidget(g)
            g.deleteLater()

        self.groupers = []
        cols = self.model.groupBy
#        print(cols)

        for c in cols:
            t = PerfGroupLabel(text=c)
            self.layout.addWidget(t)
            self.groupers.append(t)


class PerfLogSorter(QSortFilterProxyModel):
    def columnIndex(self, name):
        return self.sourceModel().columnIndex(name)

# The Main Window
class PerfLogWindow(QWidget):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        # Model init
        self.model = PerfLogModel()

        # Sorter
        self.tableSorter = PerfLogSorter()
#        self.tableSorter = TmpX()
        self.tableSorter.setSourceModel(self.model)

        # Table view
        self.tableView = QTableView(self)
        self.tableView.setModel(self.tableSorter)
        self.tableView.setSortingEnabled(True)
#        self.tableView.setModel(self.model)

        # Chart sorter
        self.chartSorter = PerfLogSorter()
#        self.chartSorter = TmpX()
        self.chartSorter.setSourceModel(self.model)
        self.chartSorter.setSortRole(groupByRole)

        # Chart view
        self.chartView = PerfChartView()
        self.chartView.setModel(self.chartSorter)
#        self.chartView.setModel(self.model)

        # Togglers
        self.toggleNormalize = QCheckBox(self, text = "Normalize", toolTip = "Show values divided by 2**exp = normalized to one operation equivalent")
        self.toggleNormalize.stateChanged.connect(lambda state:
                self.model.toggleNormalize((state == Qt.Checked)))

        self.aggregableTogglers = PerfLogAggregableController()
        self.aggregableTogglers.setModel(self.model)

        self.togglers = QHBoxLayout()
        self.togglers.addWidget(self.toggleNormalize)
        self.togglers.addWidget(self.aggregableTogglers)

        # Grouper
        self.grouper = PerfGrouper()
        self.grouper.setModel(self.model)

        # File load button
        self.fileLoadButton = QPushButton(self, text = "Load file")
        self.fileLoadButton.clicked.connect(self.fileLoadButtonClicked)

        # Copy button
        self.copyButton = QPushButton(self, text = "Copy to clipboard")
        self.copyButton.clicked.connect(self.copyButtonClicked)

        # Zoomer controller
        self.zoomer = PerfScaleSteps()
        self.chartView.setZoomer(self.zoomer)

        # Button layout
        self.buttons = QHBoxLayout()
        self.buttons.addWidget(self.fileLoadButton)
        self.buttons.addWidget(self.zoomer)
        self.buttons.addWidget(self.copyButton)

        # Layout
        self.layout = QVBoxLayout(self)
        self.layout.addWidget(self.tableView)
        self.layout.addWidget(self.chartView)
        self.layout.addLayout(self.togglers)
        self.layout.addWidget(self.grouper)
        self.layout.addLayout(self.buttons)

        # Show
        self.setLayout(self.layout)
        self.show()

    def fileLoadButtonClicked(self):
        files = QFileDialog.getOpenFileNames(self, "Select logs to load", "", "Logs (*.log);;All files (*)")
        for f in files[0]:
            self.model.addFile(f)

    def copyButtonClicked(self):
        rows = {}
        cols = {}
        yesno = {}
        for i in self.tableView.selectedIndexes():
            r = i.row()
            c = i.column()

            rows[r] = 1
            cols[c] = 1

            data = str(i.data())

            if r not in yesno:
                yesno[r] = {}

            yesno[r][c] = data

        clipboard = []
        for r in sorted(rows):
            line = []
            for c in sorted(cols):
                try:
                    line.append(yesno[r][c])
                except KeyError as e:
                    pass

            clipboard.append("\t".join(line))
        QApplication.clipboard().setText("\n".join(clipboard))

class PerfScaleSteps(QWidget):
    scaleChanged = Signal(float, float)
    scalesteps = [
            0.8, 0.9,
            1.0, 1.1, 1.2, 1.35, 1.5, 1.7, 1.85,
            2.0, 2.25, 2.5, 2.75, 3.0, 3.5, 4.0,
            5.0, 6.0, 7.5, 10.0, 12.5, 15.0, 20.0,
            25.0, 30.0, 50.0, 100.0
            ]
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._w = 2
        self._h = 2

        self.zoomOutH = QPushButton(text = "Zoom out ↔")
        self.zoomOutH.clicked.connect(lambda: self.zoomW(-1))
        self.zoomShowH = QLabel(text = "1")
        self.zoomInH = QPushButton(text = "Zoom in ↔")
        self.zoomInH.clicked.connect(lambda: self.zoomW(1))
        self.zoomOutV = QPushButton(text = "Zoom out ↕")
        self.zoomOutV.clicked.connect(lambda: self.zoomH(-1))
        self.zoomShowV = QLabel(text = "1")
        self.zoomInV = QPushButton(text = "Zoom in ↕")
        self.zoomInV.clicked.connect(lambda: self.zoomH(1))

        self.layout = QHBoxLayout(self)
        self.layout.addWidget(self.zoomOutV)
        self.layout.addWidget(self.zoomShowV)
        self.layout.addWidget(self.zoomInV)
        self.layout.addWidget(self.zoomOutH)
        self.layout.addWidget(self.zoomShowH)
        self.layout.addWidget(self.zoomInH)

        self.setLayout(self.layout)

    def width(self):
        return self.scalesteps[self._w]

    def height(self):
        return self.scalesteps[self._h]

    def zoomEmit(self):
        self.scaleChanged.emit(self.scalesteps[self._w], self.scalesteps[self._h])

    def zoomW(self, dif):
        self._w += dif
        self.zoomOutH.setEnabled(self._w != 0)
        self.zoomInH.setEnabled(self._w < len(self.scalesteps)-1)
        self.zoomShowH.setText(str(self.scalesteps[self._w]))
        self.zoomEmit()

    def zoomH(self, dif):
        self._h += dif
        self.zoomOutV.setEnabled(self._h != 0)
        self.zoomInV.setEnabled(self._h < len(self.scalesteps)-1)
        self.zoomShowV.setText(str(self.scalesteps[self._h]))
        self.zoomEmit()

class PerfChartView(QAbstractItemView):
    numpadding = 10
    toppadding = 3
    headpadding = 1
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.horizontalScrollBar().setRange(0, 0)
        self.verticalScrollBar().setRange(0, 0)
        self.viewport().resize(self.maximumViewportSize())
        self.image = None
        self.zoomer = None
        self.xscale = 1
        self.yscale = 1
        self.numwidth = 0

    def scaledSize(self):
        mvs = self.maximumViewportSize()
        return QSize(self.xscale * mvs.width(), self.yscale * mvs.height())

    def setModel(self, model):
        if self.model() is not None:
            self.model().modelReset.disconnect(self.redrawInternal)

        super().setModel(model)
        self.model().modelReset.connect(self.redrawInternal)

    def setZoomer(self, zoomer):
        if self.zoomer is not None:
            self.zoomer.scaleChanged.disconnect(self.rescale)

        self.zoomer = zoomer
        self.zoomer.scaleChanged.connect(self.rescale)

    def rescale(self, w, h):
        print("rescale", w, h)
        self.xscale = w
        self.yscale = h
        self.redrawInternal()

    # Size requirements
    def sizeHint(self):
        return QSize(1200, 400)

    def sizePolicy(self):
        return QSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)

    # Displayed offsets
    def horizontalOffset(self):
        return self.horizontalScrollBar().value()

    def verticalOffset(self):
        return self.verticalScrollBar().value()

    # In case View was looking for some lost item or whatever.
    # We haven't hidden any, we aren't guilty.
    def isItemHidden(self, index):
        print("itemhidden")
        return False

    # Where to draw
    def visualRect(self, index):
#        print("itempos", index)
        if index.column() != self.model().columnIndex("update"):
            return QRect(0,0,0,0)

        vp = self.viewport()
        
        w = vp.width()
        h = vp.height()

        n = self.model().rowCount()
        wp = w / n

        return QRect(wp * index.row(), 0, wp * (1 + index.row()), h)

    def dataChanged(self, topleft, bottomright, roles):
        print("dataChanged")
        self.redrawInternal()
        super().dataChanged(topleft, bottomright, roles)

    def redrawInternal(self):
        self.model().sort(self.model().columnIndex("update"), Qt.SortOrder.AscendingOrder)

        print("current size", self.viewport().size())
        self.viewport().resize(self.scaledSize())
        self.horizontalScrollBar().setRange(0, self.viewport().width() - self.maximumViewportSize().width())
        self.verticalScrollBar().setRange(0, self.viewport().height() - self.maximumViewportSize().height())
        print("size after resize", self.viewport().size())

        self.image = QImage(self.viewport().size(), QImage.Format_RGBA8888)

        _min = None
        _max = None

        if self.model().rowCount() == 0:
            return

        for index in range(self.model().rowCount()):
            data = self.model().data(self.model().index(index, self.model().columnIndex("update")), sortedDataSetRole)
            for point in data["data"]:
                if _min is None or _min > point:
                    _min = point
                if _max is None or _max < point:
                    _max = point

        tenp = 10 ** int(math.log10(_max))
        coef = int(_max / tenp) + 1
        _max = tenp * coef

        fm = QFontMetrics(self.font())

#        print("Paint", n, "rows ranging from", _min, "to", _max)
        lines = None
        if coef < 3:
            lines = range(0, _max, int(tenp/5))
        elif coef < 8:
            lines = range(0, _max, int(tenp/2))
        else:
            lines = range(0, _max, tenp)

        maxw = 0
        for f in lines:
            xsz = fm.size(Qt.TextSingleLine, str(f)).width()
            if xsz > maxw:
                maxw = xsz

        self.numwidth = maxw + self.numpadding

        w = self.image.width() - self.numwidth
        h = self.image.height()

        n = self.model().rowCount()
        wp = w / n

        self.image.fill(Qt.transparent)

        p = QPainter(self.image)
        p.setRenderHint(QPainter.Antialiasing)

        pointPen = QPen(Qt.gray, 0.5)
        violinPen = QPen(Qt.black, 1)
        textPen = QPen(Qt.black, 1)

        p.setPen(textPen)

        for i in lines:
            y = h * (1 - i / _max)
            p.drawLine(self.numwidth, y, self.image.width(), y)
            sz = fm.size(Qt.TextSingleLine, str(i))
            p.drawText(QRect(0, y - sz.height()/2, self.numwidth - self.numpadding, sz.height()), Qt.AlignRight, str(i))

        p.setBrush(Qt.black)

        prevKey = None
        beginKey = {}

        for index in range(self.model().rowCount()):
            data = self.model().data(self.model().index(index, self.model().columnIndex("update")), sortedDataSetRole)
            key = self.model().data(self.model().index(index, self.model().columnIndex("update")), indexRole)
            mindata = None
            maxdata = None
            p.setPen(pointPen)
            for point in data["data"]:
                if mindata is None or mindata > point:
                    mindata = point
                if maxdata is None or maxdata < point:
                    maxdata = point

                scatter = random.gauss(0, 0.1)
                x = wp * (index + 0.5 + scatter) + self.numwidth
                y = h * (1 - point / _max)
                r = 0.5

#                print("draw at", x, y, "w h _max point", w, h, _max, point)

                p.drawRect(x - r, y - r, 2*r, 2*r)
            
            sqrt2pi = math.sqrt(2*math.pi)

#            print ("len data", len(data["data"]))
#            print (-2*math.log((1.0/wp)*len(data["data"])*sqrt2pi))
            begin = mindata #- math.sqrt(-2*math.log((1.0/wp)*len(data["data"])*sqrt2pi))
            end = maxdata #+ math.sqrt(-2*math.log((1.0/wp)*len(data["data"])*sqrt2pi))

            beginY = int(h * (1 - begin / _max)) + 5
            endY = int(h * (1 - end / _max)) - 5

            p.setPen(violinPen)

            x = 0
            for y in range(endY, beginY, 1):
                ydata = _max * (1 - y / h)
                xdata = sum([(1.0/sqrt2pi) * math.exp(-0.5*(ydata - point)**2) for point in data["data"]]) / (len(data["data"])**math.sqrt(0.5))
                p.drawLine(
                        (index + 0.5 + x)*wp + self.numwidth, y - 1,
                        (index + 0.5 + xdata)*wp + self.numwidth, y
                        )
                p.drawLine(
                        (index + 0.5 - x)*wp + self.numwidth, y - 1,
                        (index + 0.5 - xdata)*wp + self.numwidth, y
                        )

                x = xdata

            p.setPen(textPen)

            if prevKey is None:
                for k in key:
                    beginKey[k] = 0
            else:
                order = sorted([k for k in key], key = lambda k: beginKey[k])
                changed = 0

                for ci in range(len(order)):
                    k = order[ci]

                    if prevKey[k] == key[k]:
                        continue

                    changed += 1
                    sz = fm.size(Qt.TextSingleLine, str(prevKey[k]))
                    avw = wp * (index - beginKey[k])

                    if sz.width() > avw:
                        continue

                    rect = QRect(wp * beginKey[k] + self.numwidth, ci*(sz.height() + self.headpadding) + self.toppadding, avw, sz.height())

                    p.drawText(rect, Qt.AlignCenter, str(prevKey[k]))

                if changed > 1:
                    x = wp * index + self.numwidth
                    curpen = p.pen()
                    p.setPen(QPen(Qt.black, 0.5 * (changed - 1)))
                    p.drawLine(x, (len(order) - changed) * (sz.height() + self.headpadding) + self.toppadding, x, h)
                    p.setPen(curpen)

                for k in key:
                    if prevKey[k] != key[k]:
                        beginKey[k] = index

            prevKey = key

        changed = sorted([ k for k in prevKey ], key=lambda k: beginKey[k])

        print(changed, [ beginKey[k] for k in changed ])
        for ci in range(len(changed)):
            k = changed[ci]

            sz = fm.size(Qt.TextSingleLine, str(prevKey[k]))
            avw = wp * (index - beginKey[k])

            if sz.width() > avw:
                break

            rect = QRect(wp * beginKey[k] + self.numwidth, ci*(sz.height() + self.headpadding) + self.toppadding, avw, sz.height())
            print("Drawing", prevKey[k], "to", rect, "size is", sz, "ci", ci)

            p.drawText(rect, Qt.AlignCenter, str(prevKey[k]))

        self.viewport().update()

    def resizeEvent(self, event):
        if self.image is None:
            return

        if self.image.size() != event.size():
            self.redrawInternal()

    def paintEvent(self, event):
        print("paint event")
        if self.image is None:
            self.redrawInternal()

        p = QPainter(self.viewport())
        p.drawPixmap(-self.horizontalOffset(), -self.verticalOffset(), QPixmap.fromImage(self.image))

        print("paint event done")

    def moveCursor(self, action, modifiers):
 #       print("move cursor", action, modifiers)
        return QModelIndex()

    def indexAt(self, point):
        vp = self.viewport()
        w = vp.width() - self.numwidth
        n = self.model().rowCount()
        wp = w / n

        if point.x() < self.numwidth:
            return QModelIndex()

        index = int((point.x() - self.numwidth) / wp)
        return self.model().index(index, self.model().columnIndex("update"))

    def scrollTo(self, index, hint):
        pass

    def setSelection(self, rect, flags):
        self.selectionModel().select(QModelIndex(), flags)

#    def event(self, event):
#        print(datetime.now(), "any event", event)
#        out = super().event(event)
#        print(datetime.now(), "returns", out)
#        return out





# Run it
qw = PerfLogWindow()
for f in sys.argv[1:]:
    if not f.startswith("-"):
        qw.model.addFile(f)

qw.tableView.resizeColumnsToContents()
app.exec_()

