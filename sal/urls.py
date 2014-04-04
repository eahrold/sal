from django.conf.urls import patterns, include, url
from django.contrib.staticfiles.urls import staticfiles_urlpatterns
from django.conf import settings

# Uncomment the next two lines to enable the admin:
from django.contrib import admin
admin.autodiscover()

if settings.RUNNING_ON_APACHE:
    sub_path = ''
else:        
    sub_path = settings.SUB_PATH


urlpatterns = patterns('',
    # Examples:
    url(r'^%slogin/$' % sub_path, 'django.contrib.auth.views.login'),
    url(r'^%slogout/$' % sub_path, 'django.contrib.auth.views.logout_then_login'),
    url(r'^%schangepassword/$' % sub_path, 'django.contrib.auth.views.password_change'),
    url(r'^%schangepassword/done/$' % sub_path, 'django.contrib.auth.views.password_change_done'),
    url(r'^%s' % sub_path, include('server.urls')),
    # Uncomment the admin/doc line below to enable admin documentation:
    url(r'^%sadmin/doc/' % sub_path, include('django.contrib.admindocs.urls')),

    # Uncomment the next line to enable the admin:
    url(r'^%sadmin/' % sub_path, include(admin.site.urls)),
    #url(r'^%s$' % sub_path, 'namer.views.index', name='home'),

)
if settings.DEBUG:
    urlpatterns += staticfiles_urlpatterns()
