# -*- coding: UTF-8 no BOM -*-

import numpy as np

try:
  import h5py
except (ImportError) as e:
  pass #  sys.stderr.write('\nREMARK: h5py module not available \n\n')

class Result():
  """
  General class for result parsing.

  Needs h5py to be installed
  """
  
  def __init__(self,resultsFile):
    self.data=h5py.File(resultsFile,"r")
    self.Npoints=self.data.attrs['Number of Materialpoints']
    print("Opened {} with {} points".format(resultsFile,self.Npoints))

  def getCrystallite(self,labels,inc,constituent=1,points=None):
    if points is None: points = np.array(np.array(range(self.Npoints)))
    results = {}
    mapping=self.data['mapping/crystallite']
    for instance in self.data['increments/%s/crystallite/'%inc]:
      dsets = list(self.data['increments/%s/crystallite/%s'%(inc,instance)].keys())
      for label in labels:
        if label in dsets and label not in results:
          shape = np.shape(self.data['increments/%s/crystallite/%s/%s'%(inc,instance,label)])[1:]
          results[label] = np.nan*np.ones(np.array((self.Npoints,)+shape))
    for myPoint in range(len(points)):
      matPoint = points[myPoint]
      pos = mapping[matPoint,constituent-1]
      if pos[0] != 0:
        try:
          for label in labels:
            results[label][matPoint,...] = self.data['increments/%s/crystallite/%s/%s'%(inc,pos[0],label)][pos[1],...]
        except:
          pass
    return results