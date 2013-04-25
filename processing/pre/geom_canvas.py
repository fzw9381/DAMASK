#!/usr/bin/env python
# -*- coding: UTF-8 no BOM -*-

import os,sys,string,re,math,numpy
from optparse import OptionParser, OptionGroup, Option, SUPPRESS_HELP


# -----------------------------
class extendedOption(Option):
# -----------------------------
# used for definition of new option parser action 'extend', which enables to take multiple option arguments
# taken from online tutorial http://docs.python.org/library/optparse.html
    
    ACTIONS = Option.ACTIONS + ("extend",)
    STORE_ACTIONS = Option.STORE_ACTIONS + ("extend",)
    TYPED_ACTIONS = Option.TYPED_ACTIONS + ("extend",)
    ALWAYS_TYPED_ACTIONS = Option.ALWAYS_TYPED_ACTIONS + ("extend",)

    def take_action(self, action, dest, opt, value, values, parser):
        if action == "extend":
            lvalue = value.split(",")
            values.ensure_value(dest, []).extend(lvalue)
        else:
            Option.take_action(self, action, dest, opt, value, values, parser)


# ----------------------- MAIN -------------------------------

identifiers = {
        'grid':   ['a','b','c'],
        'size':   ['x','y','z'],
        'origin': ['x','y','z'],
          }
mappings = {
        'grid':           lambda x: int(x),
        'size':           lambda x: float(x),
        'origin':         lambda x: float(x),
        'homogenization': lambda x: int(x),
          }


parser = OptionParser(option_class=extendedOption, usage='%prog options [file[s]]', description = """
Changes the (three-dimensional) canvas of a spectral geometry description.
""" + string.replace('$Id$','\n','\\n')
)

parser.add_option('-g', '--grid', dest='grid', type='int', nargs = 3, \
                  help='a,b,c grid of hexahedral box [unchanged]')
parser.add_option('-o', '--offset', dest='offset', type='int', nargs = 3, \
                  help='x,y,z offset from old to new origin of grid %default')
parser.add_option('-f', '--fill', dest='fill', type='int', \
                  help='(background) canvas grain index [autodetect]')
parser.add_option('-2', '--twodimensional', dest='twoD', action='store_true', \
                  help='output geom file with two-dimensional data arrangement [%default]')

parser.set_defaults(grid = [0,0,0])
parser.set_defaults(offset = [0,0,0])
parser.set_defaults(twoD = False)
parser.set_defaults(fill = 0)

(options, filenames) = parser.parse_args()

# ------------------------------------------ setup file handles ---------------------------------------  
files = []
if filenames == []:
  files.append({'name':'STDIN',
                'input':sys.stdin,
                'output':sys.stdout,
                'croak':sys.stderr,
               })
else:
  for name in filenames:
    if os.path.exists(name):
      files.append({'name':name,
                    'input':open(name),
                    'output':open(name+'_tmp','w'),
                    'croak':sys.stdout,
                    })

# ------------------------------------------ loop over input files ---------------------------------------  

for file in files:
  if file['name'] != 'STDIN': file['croak'].write(file['name']+'\n')

  #  get labels by either read the first row, or - if keyword header is present - the last line of the header

  firstline = file['input'].readline()
  m = re.search('(\d+)\s*head', firstline.lower())
  if m:
    headerlines = int(m.group(1))
    headers  = [file['input'].readline() for i in range(headerlines)]
  else:
    headerlines = 1
    headers = firstline

  content = file['input'].readlines()
  file['input'].close()

  info = {
          'grid':    numpy.array(options.grid),
          'size':    numpy.array([0.0,0.0,0.0]),
          'origin':  numpy.array([0.0,0.0,0.0]),
          'microstructures': 0,          
          'homogenization':  0,
         }

  new_header = []
  for header in headers:
    headitems = map(str.lower,header.split())
    if headitems[0] == 'resolution': headitems[0] = 'grid'
    if headitems[0] == 'dimension':  headitems[0] = 'size'
    if headitems[0] in mappings.keys():
      if headitems[0] in identifiers.keys():
        for i in xrange(len(identifiers[headitems[0]])):
          info[headitems[0]][i] = \
            mappings[headitems[0]](headitems[headitems.index(identifiers[headitems[0]][i])+1])
      else:
        info[headitems[0]] = mappings[headitems[0]](headitems[1])

  if numpy.all(options.grid == 0):
    options.grid = info['grid']
  if numpy.all(info['grid'] == 0):
    file['croak'].write('no grid info found.\n')
    continue
  if numpy.all(info['size'] == 0.0):
    file['croak'].write('no size info found.\n')
    continue
    
  microstructure = numpy.zeros(info['grid'],'i')
  i = 0
  for line in content:  
    for item in map(int,line.split()):
      microstructure[i%info['grid'][0],
                    (i/info['grid'][0])%info['grid'][1],
                     i/info['grid'][0] /info['grid'][1]] = item
      i += 1

  file['croak'].write('-- input --\n' + \
                      'grid     a b c:  %s\n'%(' x '.join(map(str,info['grid']))) + \
                      'size     x y z:  %s\n'%(' x '.join(map(str,info['size']))) + \
                      'origin   x y z:  %s\n'%(' : '.join(map(str,info['origin']))) + \
                      'homogenization:  %i\n'%info['homogenization'] + \
                      'microstructures: %i\n'%info['microstructures'])
  
  info['microstructures'] = microstructure.max()
  
  newSize = info['size']/info['grid']*options.grid
  newOrigin = info['origin']+info['size']/info['grid']*options.offset
  new_header.append("grid\ta %i\tb %i\tc %i\n"%(options.grid[0],options.grid[1],options.grid[2]))
  new_header.append("size\tx %f\ty %f\tz %f\n"%(newSize[0],newSize[1],newSize[2]))
  new_header.append("origin\tx %f\ty %f\tz %f\n"%(newOrigin[0],newOrigin[1],newOrigin[2]))
  new_header.append("homogenization\t%i\n"%info['homogenization'])
  new_header.append("microstructures\t%i\n"%info['microstructures'])

  microstructure_cropped = numpy.zeros(options.grid,'i')
  microstructure_cropped.fill({True:options.fill,False:info['microstructures']+1}[options.fill>0])
  xindex = list(set(xrange(options.offset[0],options.offset[0]+options.grid[0])) & \
                                                               set(xrange(info['grid'][0])))
  yindex = list(set(xrange(options.offset[1],options.offset[1]+options.grid[1])) & \
                                                               set(xrange(info['grid'][1])))
  zindex = list(set(xrange(options.offset[2],options.offset[2]+options.grid[2])) & \
                                                               set(xrange(info['grid'][2])))
  translate_x = [i - options.offset[0] for i in xindex]
  translate_y = [i - options.offset[1] for i in yindex]
  translate_z = [i - options.offset[2] for i in zindex]
  microstructure_cropped[min(translate_x):(max(translate_x)+1),\
                         min(translate_y):(max(translate_y)+1),\
                         min(translate_z):(max(translate_z)+1)] \
        = microstructure[min(xindex):(max(xindex)+1),\
                         min(yindex):(max(yindex)+1),\
                         min(zindex):(max(zindex)+1)]
  formatwidth = int(math.floor(math.log10(microstructure.max())+1))
  
  file['croak'].write('-- output --\n' +\
                      'grid     a b c:  %s\n'%(' x '.join(map(str,options.grid))) + \
                      'size     x y z:  %s\n'%(' x '.join(map(str,newSize)))  + \
                      'origin   x y z:  %s\n'%(' x '.join(map(str,newOrigin)))  + \
                      'microstructures: %i\n'%microstructure.max())
            
# ------------------------------------------ assemble header --------------------------------------- 

  output  = '%i\theader\n'%(len(new_header))
  output += ''.join(new_header)

# ------------------------------------- regenerate texture information ----------------------------

  for z in xrange(options.grid[2]):
    for y in xrange(options.grid[1]):
      output += {True:' ',False:'\n'}[options.twoD].join(map(lambda x: \
                                    ('%%%ii'%formatwidth)%x, microstructure_cropped[:,y,z])) + '\n'
    
# ------------------------------------------ output result ---------------------------------------  

  file['output'].write(output)

  if file['name'] != 'STDIN':
    file['output'].close()
    os.rename(file['name']+'_tmp',file['name'])
