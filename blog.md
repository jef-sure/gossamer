# Gossamer - Fine spider silk used by spiderlings for ballooning or kiting

## Зачем?

Ответов множество. Один из них, самый главный, что внутренний
графоман-программист хочет запрограммировать накопившиеся мысли.
Стоят ли эти мысли того, чтобы ради них создавать ещё один веб-фреймворк?
Это проблема графоманства -- проще написать уже накопившееся, чем убеждать
себя это не делать. 

Я попытаюсь изложить из собственного опыта и представлений о 
том "что такое хорошо" каким должен быть современный Web-framework.

## Необходимые компоненты

Задачей веб-фреймворка является отделение чистой логики приложения
от взаимодействия с окружающим миром, всю грязную работу на себя должен
взять фреймворк. Фреймворк необходимо сделать по максимуму модульным, 
чтобы не требовалось устанавливать модулей больше, чем реально
необходимо приложению. Хотя бы не намного больше. 

Основной сценарий использования веб-сервисов и приложений 
применительно к PSGI протоколу состоит в следующем:

 1. Бруазер посылает запрос;
 2. Вебсервер принимает запрос, разбирает его;
 3. Вебсервер согласно внутренних правил передаёт запрос в PSGI-сервер;
 4. Вебсервер может так же и не передавать запрос в PSGI-сервер, если
    решил обработать запрос другим образом. Например, отдать статический
    файл самостоятельно.
 5. PSGI-сервер принимает запрос, разбирает его;
 6. Решает какое PSGI-приложение отвественено за выдачу ответа и передаёт запрос ему;
 7. PSGI-приложение находит модуль, который будет обрабатывать запрос;
 8. Модуль вызывает необходимый обработчик, получает ответ;
 9. Обрабатывает ответ, чтобы получить "плоский" результат, пригодный для отдачи
    PSGI-серверу. 
10. Передаёт ответ вебсерверу;
11. Вебсервер передаёт ответ браузеру. 

Для веб-сервера и PSGI-сервера существует богатый выбор. Мне очень понравилась
эффективность связки NginX+uWSGI. Поэтому, моя цель в написании фреймворка 
PSGI-приложения.

Конфигурирование фреймворка должно быть очень гибким и удобным. 
Я уже пробовал подход, когда каждый параметр представляет из себя функцию.
Но дело в том, что большинство значений конфигурации это константы, которые
разумно сохранить в некотором человекочитаемом виде, вроде YAML. 
Впрочем, иметь любой параметр не только значением, но и вычисляемой функцией,
даёт большую гибкость. Конфигурация или любая её часть может быть изменена
в при запуске приложения.

Конфигурация делится на секции и каждая секция является так же конфигурацией.
Почти каждый компонент фреймворка имеет свою секцию в глобальной конфигурации, 
каждый внешний модуль так же. Для каждой секции в соответствующем компоненте
или модуле есть конфигурация по умолчанию. Пользовательские значения 
конфигурации сливаются с дефолтными. 

### Gossamer::Request, Gossamer::File

Объект запроса Gossamer::Request. Что он должен уметь?

1. Разбор параметров. Для протокола может быть важно откуда пришли параметры,
но приложению обычно без разницы. Поэтому надо обеспечить как "универсальный",
так и раздельный доступ к параметрам из объекта запроса.
2. Файлы, которые прислали на сервер. Ни разу не видел необходимости 
в отдельном методе получения залитых файлов, удобнее так же их положить в параметры. 
Конечно, в виде объектов Gossamer::File. Эти файлы могут понадобиться или нет, 
поэтому, они сначала лежат во временной директории, персональной для каждого запроса, а если
приложение решило их сохранить, то у него есть два метода: скопировать файл 
или создать жёсткий линк на него. Жёсткий линк эффективнее, но не работает, 
если новое место находится на другой файловой системе.
3. Хуки.

* Перед началом разбора запроса.
* После окончания разбора запроса. (в этих двух я особой надобности не вижу, но могут быть полезны для таймингов)
* Хук после разбора параметров запроса. Теоретически, он может поменять структуру разобранных параметров.
* Хук на полное завершение обработки запроса, когда необходимо почистить временную директорию от файлов, например.

#### Gossamer::Request::Deserializer::*

Встраиваемые десериализаторы.

Согласно типу содержимого тела запроса надо уметь вызывать десериализаторы для произвольных типов.
Стандартными являются типы application/x-www-form-urlencoded и multipart/form-data, так же очень часто
востребован тип application/json. Можно так же представить себе необходимость разбора XML, но в силу
не однозначного его способа разбора, лучше сделать это внешним модулем, который будет знать необходимую схему.
Можно представить и бОльшую экзотику, вроде разбора XLSX, что тоже полезно уметь.

### Gossamer::Response

Относительно простой объект. Так же необходимо обеспечить
отдачу содержимого из открытого дескриптора файла и "потоковый" ответ, 
когда содержимое отдаётся вызывемой функцией приложения постепенно, по мере готовности содержания. 

#### Gossamer::Response::Serializer::*

Он должен уметь сериализацию результата обработчика запроса, поюэтому ему
полезно уметь встраиваемые сериализаторы согласно отдаваемому типу содержимого. Тип содержимого должен быть
согласован с заголовком Accept. 

### Gossamer::Router

После того, как запрос принят, необходимо определить обработчик запроса. Основные правила
определения обработчика опираются на URL, его часть path, метод запроса и, возможно, на тип
содержания и авторизацию. Существуют реализации подобных маршрутизаторов запросов, которые
надо уметь интегрировать. Так же маршрутизатор должен уметь рекурсивные запросы, когда приложение
обращается к самому себе. Это может помочь с инкапсуляцией протоколов, например.

Хуки.

* перед началом маршрутизации
* после получения оконыательного маршрута и обработчика

### Gossamer::Handler::*

Обработчики запросов

Все обработчики на вход принципиально получают два параметра: разобранный хеш 
параметров и полный контекст запроса.

Ответы вебсервера принципиально бывают нескольких видов: AJAX, простой или 
HTML текст, готовые файлы с диска и вебсокеты. Маршрутизатор должен 
привести в итоге к одному из таких обработчиков. Так же можно иметь 
произвольные встраиваемые обработчики. Например, вебсокеты разумно 
иметь дополнительным модулем, который будет встраивать свой обработчик.

Обработчик запроса, в основном, занимается вызовом необходимой функции 
приложения, на ум приходит только отдача файлов с диска, которая отдаёт результат сразу.

Функция приложения принимает те же два параметра на вход, что и обработчик приложения, 
на выходе она отдаёт один параметр любого типа, про который должен знать сериализатор.
Или два параметра, где второй символьеый или числовой код возврата. Или три параметра, 
где третий массив или хеш заголовков. 

Все манипуляции с кодом возврата и заголовками возможны так же через конверт ответа 
из контекста. Возвращённые значения из функции имеют приоритет, возвращённые заголовки 
добавляются в те, что уже есть в конверте, при необходимости переписывая их.

Ещё возможный обработчик запросов -- обращение к данным в базу напрямую, вызов хранимых процедур.

Все обращения к функциям приложения в контексте обработчиков представляют из себя 
внутренний API приложения. 

Хуки

* После того, как завершился этап маршрутизации, но перед вызовом функции приложения
* После вызова функции приложения, но перед сериализацией ответа

### Gossamer::Context

Контекст запроса включает в себя "конверт" запроса, "конверт" ответа, объект сессии,
если есть, а так же область с временными данными.

Конверт это просто хеш с данными, которые получены из разбора запроса или 
будут использованы для сборки ответа. В области данных могут находиться 
результаты работы хуков или просто промежуточных функций приложения.

### Gossamer::Validator::*

Валидация запросов

Для валидации входящих данных, а так же, исходящего ответа, в хуках отведён 
отдельный слот, чтобы случайно другой модуль не установил свой хук на место валидации.

Валидация будет отдельными встраиваемыми модулями.

Встраиваемые модули валидации. Напримеи, капча.

### Gossamer::Session

Сессии

Внешний модуль. Под него отводятся специальный хук как для валидации данных. 
Вызывается перед валидацией входных данных. Сохранение данных сессии должно 
происходить только если были изменения содержания.

### Gossamer::Cache

Кеширование.

Разумно сделать внешним модулем, который встраивается в обработчик ответов 
после валидации исходящих данных. Где-то должны быть настройки времени 
кеширования по умолчанию и индивидуального времени кеширования дляя обработчиков.
Так же, способ принудительной инвалидации закешированного ответа.

### Gossamer::Template

Рендеринг шаблонов.

В рендерер шаблонов передаётся объект контекста, плюс желательно добавить в 
шаблонизатор функцию, которая могла бы обращаться к API приложения, тогда 
шаблоны становятся самодостаточными в плане представления и с контроллера снимается
лишняя функция подготовки индивидуальных даных для шаблона. 

### Gossamer::NLS

Локализация.

Делается внешним модулем, хуки вешаются после валидации данных.

## API

Внутренний интерфейс приложению возможно использовать прозрачно как для ответов 
веб-сервера, так и в комплексном случае, например, из шаблонов для получения данных, 
необходимых для генерации шаблона.


