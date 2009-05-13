# $Id$
#
# read slice files
#
# Author: J. Oishi (joishi@amnh.org). 
# 
#
import os
import numpy as N
import pylab as P
from npfile import npfile
from param import read_param 
from dim import read_dim 


# slice file format is either
#   plane,t (old style)
#   plane,t,slice_z2pos (new style)

def read_slices(field='uu1',datadir='data/',proc=-1,
                extension='xz',format='native',oldfile=False):
    """
    read 2D slice files and return an array of (nslices,vsize,hsize).
    """
    datadir = os.path.expanduser(datadir)
    if proc < 0:
        filename = datadir+'/slice_'+field+'.'+extension
    else:
        filename = datadir+'/proc'+str(proc)+'/slice_'+field+'.'+extension

    # global dim
    param = read_param(datadir, quiet=True)

    dim = read_dim(datadir,proc) 
    if dim.precision == 'D':
        precision = 'd'
    else:
        precision = 'f'

    # set up slice plane
    if (extension == 'xy' or extension == 'Xy'):
        hsize = dim.nx
        vsize = dim.ny
    if (extension == 'xz'):
        hsize = dim.nx
        vsize = dim.nz
    if (extension == 'yz'):
        hsize = dim.ny
        vsize = dim.nz


    infile = npfile(filename,endian=format)

    ifirst = True
    islice = 0
    t = N.zeros(1,dtype=precision)
    slices = N.zeros(1,dtype=precision)

    while 1:
        try:
            raw_data = infile.fort_read(precision)
        except ValueError:
            break
        except TypeError:
            break
        
        if oldfile:
            t = N.concatenate((t,raw_data[-1:]))
            slices = N.concatenate((slices,raw_data[:-1]))
        else:
            t = N.concatenate((t,raw_data[-2:-1]))
            slices = N.concatenate((slices,raw_data[:-2]))
        islice += 1

    output = slices[1:].reshape(islice,vsize,hsize)

    return output,t[1:]
        

def animate_slices(field='uu1',datadir='data/',proc=-1,extension='xz',format='native',
                tmin=0.,tmax=1.e38,amin=0.,amax=1.,transform='',oldfile=False):
    """
    read 2D slice files and assemble an animation.

    Options:

     field --- which variable to slice
     datadir --- path to data directory
     proc --- an integer giving the processor to read a slice from
     extension --- which plane of xy,xz,yz,Xz. for 2D this should be overwritten.
     format --- endian. one of little, big, or native (default)
     tmin --- start time
     tmax --- end time
     amin --- minimum value for image scaling
     amax --- maximum value for image scaling
     transform --- insert arbitrary numerical code to modify the slice
    """
    
    datadir = os.path.expanduser(datadir)
    if proc < 0:
        filename = datadir+'/slice_'+field+'.'+extension
    else:
        filename = datadir+'/proc'+str(proc)+'/slice_'+field+'.'+extension

    # global dim
    param = read_param(datadir)

    dim = read_dim(datadir,proc) 
    if dim.precision == 'D':
        precision = 'd'
    else:
        precision = 'f'

    # set up slice plane
    if (extension == 'xy' or extension == 'Xy'):
        hsize = dim.nx
        vsize = dim.ny
    if (extension == 'xz'):
        hsize = dim.nx
        vsize = dim.nz
    if (extension == 'yz'):
        hsize = dim.ny
        vsize = dim.nz
    plane = N.zeros((vsize,hsize),dtype=precision)

    infile = npfile(filename,endian=format)

    ax = P.axes()
    ax.set_xlabel('x')
    ax.set_ylabel('y')
    ax.set_ylim

    image = P.imshow(plane,vmin=amin,vmax=amax)

    # for real-time image display
    manager = P.get_current_fig_manager()
    manager.show()

    ifirst = True
    islice = 0
    while 1:
        try:
            raw_data = infile.fort_read(precision)
        except ValueError:
            break
        except TypeError:
            break

        if oldfile:
            t = raw_data[-1]
            plane = raw_data[:-1].reshape(vsize,hsize)
        else:
            slice_z2pos = raw_data[-1]
            t = raw_data[-2]
            plane = raw_data[:-2].reshape(vsize,hsize)
        
        if transform:
            exec('plane = plane'+transform)

        if (t > tmin and t < tmax):
            title = 't = %11.3e' % t
            ax.set_title(title)
            image.set_data(plane)
            manager.canvas.draw()
            
            if ifirst:
                print "----islice----------t---------min-------max"
            print "%10i %10.3e %10.3e %10.3e" % (islice,t,plane.min(),plane.max())
                
            ifirst = False
            islice += 1

    infile.close()



def animate_multislices(field=['uu1'],datadir='data/',proc=-1,extension='xz',format='native',
                tmin=0.,tmax=1.e38,amin=0.,amax=1.,transform='plane[0]',oldfile=False):
    """
    read a list of 2D slice files, combine them, and assemble an animation.

    Options:

     field --- list of variables to slice
     datadir --- path to data directory
     proc --- an integer giving the processor to read a slice from
     extension --- which plane of xy,xz,yz,Xz. for 2D this should be overwritten.
     format --- endian. one of little, big, or native (default)
     tmin --- start time
     tmax --- end time
     amin --- minimum value for image scaling
     amax --- maximum value for image scaling
     transform --- insert arbitrary numerical code to combine the slices
    """
    
    datadir = os.path.expanduser(datadir)
    filename=[]
    if proc < 0:
        for i in field:
            filename += [datadir+'/slice_'+i+'.'+extension]
    else:
        for i in field:
            filename += [datadir+'/proc'+str(proc)+'/slice_'+i+'.'+extension]

    # global dim
    param = read_param(datadir)

    dim = read_dim(datadir,proc) 
    if dim.precision == 'D':
        precision = 'd'
    else:
        precision = 'f'

    # set up slice plane
    if (extension == 'xy' or extension == 'Xy'):
        hsize = dim.nx
        vsize = dim.ny
    if (extension == 'xz'):
        hsize = dim.nx
        vsize = dim.nz
    if (extension == 'yz'):
        hsize = dim.ny
        vsize = dim.nz
    plane=[]
    infile=[]
    for i in filename:
        plane += [N.zeros((vsize,hsize),dtype=precision)]
        
        infile += [npfile(i,endian=format)]

    ax = P.axes()
    ax.set_xlabel('x')
    ax.set_ylabel('y')
    ax.set_ylim

    exec('plotplane ='+transform)
    image = P.imshow(plotplane,vmin=amin,vmax=amax)

    # for real-time image display
    manager = P.get_current_fig_manager()
    manager.show()

    ifirst = True
    islice = 0
    while 1:
        try:
            raw_data=[]
            for i in infile:
                raw_data += [i.fort_read(precision)]
        except ValueError:
            break
        except TypeError:
            break

        if oldfile:
            t = raw_data[0][-1]
            for i in range(len(raw_data)):
                plane[i] = raw_data[i][:-1].reshape(vsize,hsize)
        else:
            slice_z2pos = raw_data[0][-1]
            t = raw_data[0][-2]
            for i in range(len(raw_data)):
                plane[i] = raw_data[i][:-2].reshape(vsize,hsize)
        
        exec('plotplane ='+transform)

        if (t > tmin and t < tmax):
            title = 't = %11.3e' % t
            ax.set_title(title)
            image.set_data(plotplane)
            manager.canvas.draw()
            
            if ifirst:
                print "----islice----------t---------min-------max"
            print "%10i %10.3e %10.3e %10.3e" % (islice,t,plotplane.min(),plotplane.max())
                
            ifirst = False
            islice += 1

    for i in infile:
        i.close()
