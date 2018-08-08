from bs4 import BeautifulSoup
import requests
import shutil
import os
url = 'https://www.safaribooksonline.com/library/view/ccna-routing-and/9780134580715/'
domain = 'https://www.safaribooksonline.com'
output_folder = './output'
username = 'username'
password = 'SuperSecretPassword'

req = requests.get(url)
soup = BeautifulSoup(req.text, 'html.parser')

lessons = soup.find_all('li', class_='toc-level-1')
print(len(lessons))

shutil.rmtree(output_folder, ignore_errors=True)
os.makedirs(output_folder)
module_name = 'Module 0'
for lesson in lessons:
    lesson_name = lesson.a.text
    if lesson_name.startswith('Module') and not 'Summary' in lesson_name:
        module_name = lesson_name
        os.makedirs(output_folder + '/' + module_name)
        # print(module_name)
        for index, video in enumerate(lesson.ol.find_all('a')):
            video_name = str(index) + ' - ' + video.text
            video_url = domain + video.get('href')
            video_out = output_folder + '/' + module_name + '/' + video_name + '.mp4'
            # print('        ', domain + video_url)
            # print('        ', video_out)
            print ("youtube-dl -u {} -p {} --output '{}' {}".format(username, password, video_out, video_url))
    else:
        os.makedirs(output_folder + '/' + module_name + '/' + lesson_name)
        # print('   ', lesson_name)
        for index, video in enumerate(lesson.ol.find_all('a')):
            video_name = str(index) + ' - ' + video.text
            video_url = domain + video.get('href')
            video_out = output_folder + '/' + module_name + '/' + lesson_name + '/' + video_name + '.mp4'
            # print('        ', domain + video_url)
            # print('        ', video_out)
            print ("youtube-dl -u {} -p {} --output '{}' {}".format(username, password, video_out, video_url))
